require 'gtk3'
require 'etc'
require 'open3'
require 'urika'

require_relative 'connection_status'
require_relative 'credentials'
require_relative 'ui'

module Veeplet
  class Veeplet
    DISCONNECTED_STOCK_ID = 'gtk-no'
    CONNECTED_STOCK_ID = 'gtk-yes'

    def self.check_program_using_help(program)
      begin
        pid = Process.spawn("#{program} --help")
        Process.wait(pid)
        return $?.exitstatus == 0
      rescue
      end
      false
    end

    def self.get_valid_elevator()
      if (check_program_using_help('gksu'))
        "gksu --sudo-mode --message 'Elevated privileges are required to switch the selected graphics card' --"
      elsif (check_program_using_help('pkexec'))
        'pkexec'
      else
        # Not sure whether it's better to override a rarely configured askpass
        # or to try to guess one
        "sudo -HA --"
      end
    end

    def get_output_of_command(command, elevator = nil)
      final_command = elevator ? "#{elevator} #{command}" : command
      IO.popen(final_command) do |io|
        io.read().chomp()
      end
    end

    def query()
      hostname = get_output_of_command("hostname")
      user = Etc.getlogin
      connections = get_output_of_command("tailscale status")
      my_connections = connections.split(/[\r\n]/).select do |line|
        fields = line.split
        fields.size > 2 &&
          fields[1].match?(hostname) &&
          fields[2].match?(/#{user}@/)
      end

      if my_connections.empty?
        ConnectionStatus::Disconnected
      else
        ConnectionStatus::Connected
      end
    end

    def start_session()
      Open3.popen2e("#{Veeplet.get_valid_elevator} tailscale up --accept-routes") do |_, out_and_err, _|
        while (line = out_and_err.gets)
          url = Urika.get_first_url(line)
          get_output_of_command("xdg-open \"https://#{url}\"") if url
        end
      end
    end

    def connect()
      case @status
      when ConnectionStatus::Disconnected
        start_session
      else
        puts("Don't know how to connect when current status is #{@status}")
      end
      refresh_display()
    end

    def disconnect()
      puts("Warning: trying to disconnect when state is #{@status}") unless @status == ConnectionStatus::Connected
      get_output_of_command("tailscale down", Veeplet.get_valid_elevator)
      refresh_display()
    end

    def refresh_display()
      @status = query()
      update_status_icon(@status)
      update_menu_item_visibilities(@status)
    end

    def update_menu_item_visibilities(status)
      @connect.visible = status != ConnectionStatus::Connected
      @disconnect.visible = status == ConnectionStatus::Connected
    end

    def update_status_icon(status)
      @icon.stock = status == ConnectionStatus::Connected ? CONNECTED_STOCK_ID : DISCONNECTED_STOCK_ID
      @icon.tooltip_text = "Tailscale (#{status})"
    end

    def enable()
      @status = query()
      @menu = Gtk::Menu.new()
      @connect = Gtk::MenuItem.new(:label => 'Connect')
      @connect.signal_connect('activate'){ |_| connect() }
      @menu.append(@connect)
      @disconnect = Gtk::MenuItem.new(:label => 'Disconnect')
      @disconnect.signal_connect('activate'){ |_| disconnect() }
      @menu.append(@disconnect)
      @menu.show_all()
      update_menu_item_visibilities(@status)

      @icon = Gtk::StatusIcon.new()
      @icon.signal_connect('activate') do |icon|
        @menu.popup(nil, nil, 1, Gdk::CURRENT_TIME) { |menu, x, y, _| Gtk::StatusIcon.position_menu(menu, x, y, icon) }
      end
      @icon.signal_connect('popup-menu') do |icon, button, time|
        @menu.popup(nil, nil, button, time) { |menu, x, y, _| Gtk::StatusIcon.position_menu(menu, x, y, icon) }
      end
      update_status_icon(@status)

      # Refresh every 10s in case there's a network change not triggered by us
      GLib::Timeout.add(10000) do
        refresh_display()
        true
      end
    end
  end
end

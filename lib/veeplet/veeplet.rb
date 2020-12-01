require 'gtk3'
require_relative 'connection_status'
require_relative 'credentials'
require_relative 'ui'

module Veeplet
  class Veeplet
    DISCONNECTED_STOCK_ID = 'gtk-no'
    CONNECTED_STOCK_ID = 'gtk-yes'
    CONFIGURATION_PATTERN = Regexp.new("^-----.*\\s#{Credentials::CONFIG_NAME}", Regexp::MULTILINE)
    SESSION_PATTERN = Regexp.new("^-----.*\\sConfig name: #{Credentials::CONFIG_NAME}", Regexp::MULTILINE)
    CONNECTED_PATTERN = Regexp.new('Status: Connection, Client connected', Regexp::MULTILINE)
    PAUSED_PATTERN = Regexp.new('Status: Connection, Client connection paused', Regexp::MULTILINE)
    USERNAME_PATTERN = Regexp.new('auth user\s*name:', Regexp::MULTILINE | Regexp::IGNORECASE)
    PASSWORD_PATTERN = Regexp.new('auth password:', Regexp::MULTILINE | Regexp::IGNORECASE)
    TWO_FACTOR_PATTERN = Regexp.new('second factor:', Regexp::MULTILINE | Regexp::IGNORECASE)

    def get_output_of_command(command)
      output = nil
      IO.popen(command) { |io|
        output = io.read().chomp()
      }
      output
    end

    def query()
      configs = get_output_of_command('openvpn3 configs-list')
      return ConnectionStatus::Unconfigured unless configs.match?(CONFIGURATION_PATTERN)

      sessions = get_output_of_command('openvpn3 sessions-list')
      return ConnectionStatus::Disconnected unless sessions.match?(SESSION_PATTERN)

      return ConnectionStatus::Connected if sessions.match?(CONNECTED_PATTERN)
      return ConnectionStatus::Paused if sessions.match?(PAUSED_PATTERN)

      # Unknown, better act like we're disconnected
      return ConnectionStatus::Disconnected
    end

    def load_configuration()
      get_output_of_command("openvpn3 config-import --config #{Credentials::CONFIG_PATH} --name #{Credentials::CONFIG_NAME} --persistent")
    end

    def prompt_response(io, prompt_pattern, response)
      read_length = 8192
      output = ''
      while output.empty?
        # Wait until we're ready to read
        IO.select([io])
        output = io.read_nonblock(read_length, :exception => false).chomp()
      end

      # puts(output)
      return false unless output.match?(prompt_pattern)

      # Wait until we're ready to write
      IO.select(nil, [io])
      io.write_nonblock("#{response}\n", :exception => false)
      return true
    end

    def start_session(username, password, two_factor)
      if !username || !password
        puts("Invalid username or password")
        return false
      end

      username.chomp!()
      password.chomp!()
      two_factor.chomp!() if two_factor

      if username.empty? || password.empty?
        puts("Invalid username or password")
        return false
      end

      IO.popen("openvpn3 session-start --config #{Credentials::CONFIG_NAME}", 'r+') do |io|
        unless prompt_response(io, USERNAME_PATTERN, username)
          puts("Error starting session, couldn't get username prompt")
          return false
        end
        unless prompt_response(io, PASSWORD_PATTERN, password)
          puts("Error starting session, couldn't get password prompt")
          return false
        end

        # This is allowed to fail, there may not be a two-factor prompt
        prompt_response(io, TWO_FACTOR_PATTERN, two_factor)

        return true
      end
    end

    def connect()
      case @status
      when ConnectionStatus::Unconfigured
        load_configuration()
        UI.authenticate { |username, password, two_factor| start_session(username, password, two_factor) }
      when ConnectionStatus::Disconnected
        UI.authenticate { |username, password, two_factor| start_session(username, password, two_factor) }
      when ConnectionStatus::Paused
        get_output_of_command("openvpn3 session-manage --resume --config #{Credentials::CONFIG_NAME}")
      else
        puts("Don't know how to connect when current status is #{@status}")
      end
      refresh_display()
    end

    def disconnect()
      puts("Warning: trying to disconnect when state is #{@status}") unless @status == ConnectionStatus::Connected
      get_output_of_command("openvpn3 session-manage --pause --config #{Credentials::CONFIG_NAME}")
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
      @icon.tooltip_text = "OpenVPN (#{status})"
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
      GLib::Timeout.add(10000){ refresh_display() }
    end
  end
end

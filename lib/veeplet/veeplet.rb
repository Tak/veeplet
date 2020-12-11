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

      case sessions
      when CONNECTED_PATTERN
        ConnectionStatus::Connected
      when PAUSED_PATTERN
        ConnectionStatus::Paused
      else
        # Unknown, better act like we're disconnected
        ConnectionStatus::NeedsRestart
      end
    end

    def load_configuration()
      get_output_of_command("openvpn3 config-import --config #{Credentials::CONFIG_PATH} --name #{Credentials::CONFIG_NAME} --persistent")
    end

    def read_prompt(io, prompt_pattern)
      # 5-second timeout
      wait_time = Time.now + 10
      read_length = 8192
      output = ''
      while Time.now < wait_time && !output.match?(prompt_pattern)
        # Wait until we're ready to read
        IO.select([io])
        read = io.read_nonblock(read_length, :exception => false)
        output += read if read
      end

      unless output.match?(prompt_pattern)
        puts("Got non-matching output:\n#{output}")
        return false
      end
      yield output
      return true
    end

    def write_response(io, response)
      # Wait until we're ready to write
      IO.select(nil, [io])
      io.write_nonblock("#{response}\n", :exception => false)
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
        unless read_prompt(io, USERNAME_PATTERN) { |prompt| write_response(io, username) }
          puts("Error starting session, couldn't get username prompt")
          return false
        end
        unless read_prompt(io, PASSWORD_PATTERN){ |prompt| write_response(io, password) }
          puts("Error starting session, couldn't get password prompt")
          return false
        end

        # This is allowed to fail, there may not be a two-factor prompt
        read_prompt(io, TWO_FACTOR_PATTERN){ |prompt| write_response(io, two_factor) }
        return true
      end
    end

    def resume()
      IO.popen("openvpn3 session-manage --resume --config #{Credentials::CONFIG_NAME}", 'r+') do |io|
        # There may or may not be a two-factor prompt here
        read_prompt(io, TWO_FACTOR_PATTERN){ |prompt|
          UI.prompt_two_factor("Authenticate #{Credentials::CONFIG_NAME}"){ |two_factor| write_response(io, two_factor) }
        }
      end
    end

    # TODO: Refactor this after more exercise
    def restart_session(username, password, two_factor)
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

      IO.popen("openvpn3 session-manage --restart --config #{Credentials::CONFIG_NAME}", 'r+') do |io|
        unless read_prompt(io, USERNAME_PATTERN) { |prompt| write_response(io, username) }
          puts("Error starting session, couldn't get username prompt")
          return false
        end
        unless read_prompt(io, PASSWORD_PATTERN){ |prompt| write_response(io, password) }
          puts("Error starting session, couldn't get password prompt")
          return false
        end

        # This is allowed to fail, there may not be a two-factor prompt
        read_prompt(io, TWO_FACTOR_PATTERN){ |prompt| write_response(io, two_factor) }
        return true
      end
    end

    def connect()
      case @status
      when ConnectionStatus::Unconfigured
        load_configuration()
        UI.authenticate("Authenticate #{Credentials::CONFIG_NAME}") { |username, password, two_factor| start_session(username, password, two_factor) }
      when ConnectionStatus::Disconnected
        UI.authenticate("Authenticate #{Credentials::CONFIG_NAME}") { |username, password, two_factor| start_session(username, password, two_factor) }
      when ConnectionStatus::Paused
        resume()
      when ConnectionStatus::NeedsRestart
        UI.authenticate("Authenticate #{Credentials::CONFIG_NAME}") { |username, password, two_factor| restart_session(username, password, two_factor) }
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
      GLib::Timeout.add(10000) do
        refresh_display()
        true
      end
    end
  end
end

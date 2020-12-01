require 'gtk3'

module Veeplet
  class Veeplet
    DISCONNECTED_STOCK_ID = 'gtk-no'
    CONNECTED_STOCK_ID = 'gtk-yes'

    def query()
      false
    end

    def connect()
      puts('Connect')
    end

    def disconnect()
      puts('Disconnect')
    end

    def update_menu_item_visibilities(connected)
      @connect.visible = !connected
      @disconnect.visible = connected
    end

    def update_status_icon(connected)
      @icon.stock = connected ? CONNECTED_STOCK_ID : DISCONNECTED_STOCK_ID
    end

    def enable()
      connected = query()
      query_display = connected ? 'Connected' : 'Disconnected'
      @icon = Gtk::StatusIcon.new()
      # TODO: better icon
      @icon.tooltip_text = "OpenVPN (#{query_display})"
      @icon.visible = true
      update_status_icon(connected)

      @menu = Gtk::Menu.new()
      @connect = Gtk::MenuItem.new(:label => 'Connect')
      @connect.signal_connect('activate'){ |item|
        connect()
      }
      @menu.append(@connect)

      @disconnect = Gtk::MenuItem.new(:label => 'Disconnect')
      @disconnect.signal_connect('activate'){ |item|
        disconnect()
      }
      @menu.append(@disconnect)
      @menu.show_all()
      update_menu_item_visibilities(connected)

      @icon.signal_connect('activate') do |icon|
        @menu.popup(nil, nil, 1, Gdk::CURRENT_TIME) { |menu, x, y, push_in| Gtk::StatusIcon.position_menu(menu, x, y, icon) }
      end
      @icon.signal_connect('popup-menu') do |icon, button, time|
        @menu.popup(nil, nil, button, time) { |menu, x, y, push_in| Gtk::StatusIcon.position_menu(menu, x, y, icon) }
      end
    end
  end
end

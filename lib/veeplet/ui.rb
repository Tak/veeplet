require 'gtk3'

module Veeplet
  class UI
    def self.authenticate()
      builder = Gtk::Builder.new()
      builder.add_from_file('ui.glade')
      builder.connect_signals{ |handler| method(handler) }

      dialog = builder['dialog_authentication']
      response = dialog.run()
      username = nil
      password = nil
      two_factor = nil
      if response == Gtk::ResponseType::OK
        username = builder['entry_username'].text
        password = builder['entry_password'].text
        two_factor = builder['entry_2fa'].text
      end
      dialog.destroy()
      yield username, password, two_factor
    end
  end
end
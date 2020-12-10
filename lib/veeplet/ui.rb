require 'gtk3'

module Veeplet
  class UI
    def self.load_builder()
      builder = Gtk::Builder.new()
      builder.add_from_file('ui.glade')
      builder.connect_signals{ |handler| method(handler) }
      return builder
    end

    def self.authenticate(title)
      builder = load_builder()

      dialog = builder['dialog_authentication']
      dialog.title = title
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

    def self.prompt_two_factor(title)
      builder = load_builder()
      ['label_username', 'entry_username', 'label_password', 'label_password'].each do |thing|
        builder[thing].hide()
      end

      dialog = builder['dialog_authentication']
      dialog.title = title
      response = dialog.run()
      two_factor = nil
      if response == Gtk::ResponseType::OK
        two_factor = builder['entry_2fa'].text
      end
      dialog.destroy()
      yield two_factor
    end
  end
end
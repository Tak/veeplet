require 'ruby-enum'

class ConnectionStatus
  include Ruby::Enum

  define :Unconfigured, 'Unconfigured'
  define :Connected, 'Connected'
  define :Disconnected, 'Disconnected'
  define :Paused, 'Paused'
end

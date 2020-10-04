# typed: false
require 'logger'
require 'colorized_string'

module Kuby
  class BasicLogger < Logger
    def initialize(*args)
      super

      self.formatter = proc do |_severity, _datetime, _progname, msg|
        "#{msg}\n"
      end
    end

    def info(msg, *args)
      super(ColorizedString[msg].yellow, *args)
    end

    def fatal(msg, *args)
      super(ColorizedString[msg].red, *args)
    end

    # adhere to the "CLI" interface
    def with_pipes(_out = STDOUT, err = STDERR)
      previous_logdev = @logdev || STDERR
      reopen(err)
      yield
    ensure
      reopen(previous_logdev)
    end

    def last_status
      nil
    end
  end
end

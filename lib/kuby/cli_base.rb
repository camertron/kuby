# typed: true
require 'open3'
module Kuby
  class CLIBase
    def last_status
      Thread.current[status_key]
    end

    def before_execute(&block)
      @before_execute ||= []
      @before_execute << block
    end

    def after_execute(&block)
      @after_execute ||= []
      @after_execute << block
    end

    def with_pipes(out = STDOUT, err = STDERR)
      previous_stdout = stdout
      previous_stderr = stderr
      self.stdout = out
      self.stderr = err
      yield
    ensure
      self.stdout = previous_stdout
      self.stderr = previous_stderr
    end

    def stdout
      Thread.current[stdout_key] || STDOUT
    end

    def stdout=(new_stdout)
      Thread.current[stdout_key] = new_stdout
    end

    def stderr
      Thread.current[stderr_key] || STDERR
    end

    def stderr=(new_stderr)
      Thread.current[stderr_key] = new_stderr
    end

    private

    def open3_w(env, cmd, opts = {})
      run_before_callbacks(cmd)
      cmd_s = cmd.join(' ')

      Open3.popen3(env, cmd_s, opts) do |p_stdin, p_stdout, p_stderr, wait_thread|
        Thread.new(stdout) do |t_stdout|
          p_stdout.each { |line| t_stdout.puts(line) }
        rescue IOError
        end

        Thread.new(stderr) do |t_stderr|
          p_stderr.each { |line| t_stderr.puts(line) }
        rescue IOError
        end

        yield(p_stdin).tap do
          p_stdin.close
          self.last_status = wait_thread.value
          run_after_callbacks(cmd)
          wait_thread.join
        end
      end
    end

    def execc(cmd)
      run_before_callbacks(cmd)
      cmd_s = cmd.join(' ')
      exec(cmd_s)
    end

    def systemm(cmd)
      if stdout == STDOUT && stderr == STDERR
        systemm_default(cmd)
      else
        systemm_open3(cmd)
      end
    end

    def systemm_default(cmd)
      run_before_callbacks(cmd)
      cmd_s = cmd.join(' ')
      system(cmd_s).tap do
        self.last_status = $?
        run_after_callbacks(cmd)
      end
    end

    def systemm_open3(cmd)
      run_before_callbacks(cmd)
      cmd_s = cmd.join(' ')

      Open3.popen3(cmd_s) do |p_stdin, p_stdout, p_stderr, wait_thread|
        Thread.new(stdout) do |t_stdout|
          p_stdout.each { |line| t_stdout.puts(line) }
        rescue IOError
        end

        Thread.new(stderr) do |t_stderr|
          p_stderr.each { |line| t_stderr.puts(line) }
        rescue IOError
        end

        p_stdin.close
        self.last_status = wait_thread.value
        run_after_callbacks(cmd)
        wait_thread.join
      end
    end

    def backticks(cmd)
      if stdout == STDOUT && stderr == STDERR
        backticks_default(cmd)
      else
        backticks_open3(cmd)
      end
    end

    def backticks_default(cmd)
      run_before_callbacks(cmd)
      cmd_s = cmd.join(' ')
      `#{cmd_s}`.tap do
        self.last_status = $?
        run_after_callbacks(cmd)
      end
    end

    def backticks_open3(cmd)
      run_before_callbacks(cmd)
      cmd_s = cmd.join(' ')
      result = StringIO.new

      Open3.popen3(cmd_s) do |p_stdin, p_stdout, p_stderr, wait_thread|
        Thread.new do
          p_stdout.each { |line| result.puts(line) }
        rescue IOError
        end

        Thread.new(stderr) do |t_stderr|
          p_stderr.each { |line| t_stderr.puts(line) }
        rescue IOError
        end

        p_stdin.close
        self.last_status = wait_thread.value
        run_after_callbacks(cmd)
        wait_thread.join
      end

      result.string
    end

    def run_before_callbacks(cmd)
      (@before_execute || []).each { |cb| cb.call(cmd) }
    end

    def run_after_callbacks(cmd)
      (@after_execute || []).each { |cb| cb.call(cmd, last_status) }
    end

    def last_status=(status)
      Thread.current[status_key] = status
    end

    def status_key
      raise NotImplementedError, "#{__method__} must be defined in derived classes"
    end

    def stdout_key
      raise NotImplementedError, "#{__method__} must be defined in derived classes"
    end

    def stderr_key
      raise NotImplementedError, "#{__method__} must be defined in derived classes"
    end
  end
end

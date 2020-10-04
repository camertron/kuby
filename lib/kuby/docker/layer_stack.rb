# typed: strict

module Kuby
  module Docker
    class LayerStack
      extend T::Sig
      extend T::Generic

      Elem = type_member(fixed: Layer)

      include Enumerable

      sig { returns(T::Array[Symbol]) }
      attr_reader :stack

      sig { returns(T::Hash[Symbol, Layer]) }
      attr_reader :layers

      sig { void }
      def initialize
        @stack = T.let([], T::Array[Symbol])
        @layers = T.let({}, T::Hash[Symbol, Layer])
      end

      sig do
        override.params(
          block: T.nilable(T.proc.params(layer: Layer).void)
        )
                .void
      end
      def each
        return to_enum(T.must(__method__)) unless block_given?

        @stack.each { |name| yield T.must(layers[name]) }
      end

      sig do
        params(
          name: Symbol,
          layer: T.nilable(Layer),
          block: T.nilable(T.proc.params(df: Dockerfile).void)
        )
          .void
      end
      def use(name, layer = nil, &block)
        stack << name

        if layer
          layers[name] = layer
        elsif block_given?
          layers[name] = InlineLayer.new(block)
        else
          raise "Must either pass a layer object or a block to `#{__method__}'"
        end
      end

      sig do
        params(
          name: Symbol,
          layer: T.nilable(T.any(Layer, T::Hash[Symbol, T.untyped])),
          options: T::Hash[Symbol, T.untyped],
          block: T.nilable(T.proc.params(df: Dockerfile).void)
        )
          .void
      end
      def insert(name, layer = nil, options = {}, &block)
        # this is truly gross but it's the only way I can think of to be able
        # to call insert these two ways:
        #
        # insert :foo, FooLayer.new, before: :bundler_phase
        # insert :foo, before: :bundler_phase do
        #   ...
        # end
        if layer.is_a?(Hash)
          insert(name, nil, options.merge(layer), &block)
          return
        end

        existing_name = options[:before] || options[:after]
        idx = stack.index(existing_name)

        raise ArgumentError, "Could not find existing layer '#{existing_name}'" unless idx

        idx += 1 if options[:after]
        stack.insert(idx, name)

        if layer
          layers[name] = layer
        elsif block_given?
          layers[name] = InlineLayer.new(block)
        else
          raise "Must either pass a layer object or a block to `#{__method__}'"
        end
      end

      sig { params(name: Symbol).void }
      def delete(name)
        stack.delete(name)
        layers.delete(name)
      end

      sig { params(name: Symbol).returns(T::Boolean) }
      def includes?(name)
        layers.include?(name)
      end
    end
  end
end

# typed: strict

module Kuby
  module Docker
    class PackageList
      extend T::Sig
      extend T::Generic

      Elem = type_member(fixed: Distro::PackageImpl)

      include Enumerable

      sig { returns(T::Array[Distro::PackageImpl]) }
      attr_reader :packages

      sig { params(package_tuples: T::Array[[Symbol, T.nilable(String)]]).void }
      def initialize(package_tuples)
        @packages = T.let([], T::Array[Distro::PackageImpl])
        package_tuples.each { |name, version| add(name, version) }
      end

      sig { params(name: Symbol).returns(T.nilable(Distro::PackageImpl)) }
      def [](name)
        packages.find { |pkg| pkg.name == name }
      end

      sig { params(name: Symbol, version: T.nilable(String)).void }
      def add(name, version = nil)
        packages << Packages::Package.new(name, version)
      end

      sig { params(name: String).void }
      def delete(name)
        packages.delete_if { |pkg| pkg.name == name }
      end

      sig do
        override.params(
          block: T.proc.params(package: Distro::PackageImpl).void
        )
                .void
      end
      def each(&block)
        packages.each(&block)
      end

      sig { returns(T::Boolean) }
      def empty?
        packages.empty?
      end
    end
  end
end

# typed: strict

module Kuby
  module Docker
    class Distro
      extend T::Sig
      extend T::Helpers

      abstract!

      PackageImpl = T.type_alias do
        T.any(Packages::Package, Packages::ManagedPackage, Packages::SimpleManagedPackage)
      end

      ManagedPackageImpl = T.type_alias do
        T.any(Packages::ManagedPackage, Packages::SimpleManagedPackage)
      end

      sig { params(phase: Layer).void }
      def initialize(phase)
        @phase = phase
      end

      sig { params(packages: T::Array[PackageImpl], into: Dockerfile).void }
      def install(_packages, into:)
        raise NotImplementedError,
              "#{__method__} must be defined in derived classes"
      end

      sig { returns(T::Array[[Symbol, T.nilable(String)]]) }
      def default_packages
        raise NotImplementedError,
              "#{__method__} must be defined in derived classes"
      end

      sig { returns(String) }
      def shell_exe
        raise NotImplementedError,
              "#{__method__} must be defined in derived classes"
      end
    end
  end
end

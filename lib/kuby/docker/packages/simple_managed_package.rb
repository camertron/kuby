# typed: strict

module Kuby
  module Docker
    module Packages
      class SimpleManagedPackage
        extend T::Sig

        sig { returns(String) }
        attr_reader :name

        sig { params(name: String).void }
        def initialize(name)
          @name = name
        end

        sig { params(distro: Symbol).returns(String) }
        def package_name_for(_distro)
          name
        end

        sig { params(ver: String).returns(T.self_type) }
        def with_version(_ver)
          self
        end

        sig { returns(T::Boolean) }
        def managed?
          true
        end
      end
    end
  end
end

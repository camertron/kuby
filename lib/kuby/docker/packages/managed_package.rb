# typed: strict

module Kuby
  module Docker
    module Packages
      class ManagedPackage
        extend T::Sig

        sig { returns(Symbol) }
        attr_reader :name

        sig { returns(T::Hash[Symbol, String]) }
        attr_reader :names_per_distro

        sig do
          params(
            name: Symbol,
            names_per_distro: T::Hash[Symbol, String]
          )
            .void
        end
        def initialize(name, names_per_distro)
          @name = name
          @names_per_distro = names_per_distro
        end

        sig { params(distro: Symbol).returns(String) }
        def package_name_for(distro)
          names_per_distro.fetch(distro) do
            raise UnsupportedDistroError, "Couldn't install #{name} "\
              "because #{distro} is an unsupported distro"
          end
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

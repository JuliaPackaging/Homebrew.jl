# This file contains the necessary ingredients to create a PackageManager for BinDeps
using BinDeps
import BinDeps: PackageManager, can_use, package_available, libdir, generate_steps, LibraryDependency, provider
import Base: show

mutable struct HB <: PackageManager
    packages
end

show(io::IO, hb::HB) = write(io, "Homebrew Bottles ",
    join(isa(hb.packages, AbstractString) ? [hb.packages] : hb.packages,", "))



# Only return true on Darwin platforms
can_use(::Type{HB}) = Sys.KERNEL == :Darwin

function package_available(p::HB)
    !can_use(HB) && return false
    pkgs = p.packages
    if isa(pkgs, AbstractString)
        pkgs = [pkgs]
    end

    # For each package, see if we can get info about it.  If not, fail out
    for pkg in pkgs
        try
            info(pkg)
        catch
            return false
        end
    end
    return true
end

libdir(p::HB, dep) = joinpath(brew_prefix, "lib")

provider(::Type{HB}, packages::Vector{T}; opts...) where {T <: AbstractString} = HB(packages)

function generate_steps(dep::LibraryDependency, p::HB, opts)
    pkgs = p.packages
    if isa(pkgs, AbstractString)
        pkgs = [pkgs]
    end
    ()->install(pkgs)
end

function install(pkgs)
    for pkg in pkgs
        add(pkg)
    end
end

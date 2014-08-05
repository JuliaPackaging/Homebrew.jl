# This file contains the necessary ingredients to create a PackageManager for BinDeps
using BinDeps
import BinDeps: PackageManager, can_use, package_available, libdir, generate_steps, LibraryDependency, provider
import Base: show

type HB <: PackageManager
    packages
end

show(io::IO, hb::HB) = write(io, "Homebrew Bottles ",
    join(isa(hb.packages,String) ? [hb.packages] : hb.packages,", "))



# Only return true on Darwin platforms
can_use(::Type{HB}) = OS_NAME == :Darwin

function package_available(p::HB)
    !can_use(HB) && return false
    pkgs = p.packages
    if isa(pkgs,String)
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

provider(::Type{HB}, packages::Vector{ASCIIString}; opts...) = HB(packages)

function generate_steps(dep::LibraryDependency, p::HB, opts)
    if get(opts, :force_rebuild, false)
        error("Will not force Homebrew to rebuild dependency \"$(dep.name)\".\n"*
              "Please make any necessary adjustments manually (This might just be a version upgrade)")
    end
    pkgs = p.packages
    if isa(pkgs,String)
        pkgs = [pkgs]
    end
    ()->install(pkgs)
end

function install(pkgs)
    for pkg in pkgs
        add(pkg)
    end
end

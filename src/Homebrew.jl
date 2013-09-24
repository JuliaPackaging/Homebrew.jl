module Homebrew

using Base.Git
import Base: show


# Homebrew prefix
const brew_prefix = Pkg.dir("Homebrew", "deps", "usr")
const tappath = joinpath(brew_prefix,"Library","Taps","staticfloat-juliadeps")

const BREW_URL = "https://github.com/staticfloat/homebrew.git"
const BREW_BRANCH = "kegpkg"
const BOTTLE_SERVER = "http://archive.org/download/julialang/"


function init()
    # Let's see if Homebrew is installed.  If not, let's do that first!
    install_brew()

    # Update environment variables such as PATH, DL_LOAD_PATH, etc...
    update_env()
end

function link_bundled_dylibs()
    # This function links dylibs that are bundled with Julia (e.g. libgmp) into
    # Homebrew's lib/ folder so that dependencies such as gnutls can find them
    bundled_dylibs = ["libgmp"]

    jlib = abspath(joinpath(JULIA_HOME,"..","lib","julia"))
    mkpath(joinpath(brew_prefix,"lib"))

    # Search for the bundled_dylibs in our private lib directory
    for f in readdir(jlib)
        symlink = abspath(joinpath(brew_prefix,"lib",basename(f)))
        for d in bundled_dylibs
            if contains(f, d) && !isfile(symlink)
                run(`ln -fs $(joinpath(jlib,f)) $symlink`)
            end
        end
    end
end

function install_brew()
    # Ensure brew_prefix exists
    try mkdir(brew_prefix); end

    # Make sure brew isn't already installed
    if !isexecutable( joinpath(brew_prefix, "bin", "brew") )
        # Clone brew into brew_prefix
        Base.info("Cloning brew from $BREW_URL")
        try Git.run(`clone $BREW_URL -b $BREW_BRANCH $brew_prefix`)
        catch
            warn("Could not clone $BREW_URL/$BREW_BRANCH into $brew_prefix!")
            rethrow()
        end
    end

    if !isexecutable(joinpath(brew_prefix,"bin","otool"))
        # Download/install packaged install_name_tools
        try run(`curl --location $BOTTLE_SERVER/cctools_bundle.tar.gz` |> `tar xz -C $(joinpath(brew_prefix,"bin"))`)
        catch
            warn("Could not download/extract $BOTTLE_SERVER/cctools_bundle.tar.gz into $(joinpath(brew_prefix,"bin"))!")
            rethrow()
        end
    end

    if !isdir(tappath)
        # Tap staticfloat/juliadeps
        try run(`$(joinpath(brew_prefix, "bin", "brew")) tap staticfloat/juliadeps --quiet`)
        catch
            warn( "Could not tap staticfloat/juliadeps!" )
            rethrow()
        end
    end

    # link bundled dylibs into $brew_prefix/lib
    link_bundled_dylibs()
end

function update()
    Git.run(`pull origin $BREW_BRANCH`, dir=brew_prefix)
    Git.run(`pull`, dir=tappath)
end

# Update environment variables so we can natively call brew, otool, etc...
function update_env()
    if length(Base.search(ENV["PATH"], joinpath(brew_prefix, "bin"))) == 0
        ENV["PATH"] = "$(realpath(joinpath(brew_prefix, "bin"))):$(joinpath(brew_prefix, "sbin")):$(ENV["PATH"])"
    end

    if !(joinpath(brew_prefix,"lib") in DL_LOAD_PATH)
        push!(DL_LOAD_PATH, joinpath(brew_prefix, "lib") )
    end
    return
end

immutable BrewPkg
    name::ASCIIString
    version::ASCIIString

    BrewPkg(n, v) = new(n,v)
    BrewPkg(a::Array) = new(a[1], a[2])
end

function prefix()
    brew_prefix
end

function prefix(pkg)
    split(split(info(pkg),"\n")[3])[1]
end

function show(io::IO, b::BrewPkg)
    write(io, "$(b.name): $(b.version)")
end

# List all installed packages as a list of (name,version) lists
function list()
    brew_list = readchomp(`brew list --versions`)
    if length(brew_list) != 0
        [BrewPkg(split(f)) for f in split(brew_list,"\n")]
    else
        []
    end
end

# Print out info for a specific package
function info(pkg)
    readchomp(`brew info staticfloat/juliadeps/$pkg`)
end

# Install a package
function add(pkg, version=nothing, git_hash=nothing)
    # First, check to make sure we don't already have this version installed
    installed_packages = list()
    if( version != nothing )
        # If they explicitly ask for a version, let's make sure we don't already have it
        if installed(pkg, version)
            return
        end
    else
        latest_version = split(info(pkg))[3]

        # If they implicitly ask for the latest, also makre sure we don't already have it
        if installed( pkg, latest_version )
            return
        end
    end

    cd(tappath) do
        # If we request a specific version, we'll need to checkout the given git hash
        if version != nothing && git_hash != nothing
            run(`git checkout $git_hash $pkg.rb`)
        end
        if linked( pkg )
            run(`brew unlink --quiet $pkg`)
        end
        run(`brew install staticfloat/juliadeps/$pkg`)
        if git_hash != nothing
            run(`git checkout HEAD $pkg.rb`)
        end
    end
end

function search(pkg)
    isfile(joinpath(tappath,"$(pkg).rb"))
end

function installed(pkg, version = nothing)
    installed_packages = list()
    if version != nothing
        any([p.name == pkg && p.version == version for p in list()])
    else
        isdir(joinpath(brew_prefix,"Cellar",pkg))
    end
end

function linked(pkg)
    return islink(joinpath(brew_prefix,"Library","LinkedKegs",pkg))
end

function rm(pkg)
    run(`brew rm --force $pkg`)
end

function rm(pkg::BrewPkg)
    rm(pkg.name)
end

# Include our own, personal bindeps integration stuff
include("bindeps.jl")

init()
end # module

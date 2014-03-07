module Homebrew

import Base: show
if VERSION >= v"0.3.0-"
    import Base: Pkg.Git
else
    import Base: Git
end

# Homebrew prefix
const brew_prefix = Pkg.dir("Homebrew", "deps", "usr")
const brew = joinpath(brew_prefix,"bin","brew")
const tappath = joinpath(brew_prefix,"Library","Taps","staticfloat-juliadeps")

const BREW_URL = "https://github.com/staticfloat/homebrew.git"
const BREW_BRANCH = "kegpkg"
const BOTTLE_SERVER = "http://s3.amazonaws.com/julialang/bin/osx/extras"


function init()
    # Let's see if Homebrew is installed.  If not, let's do that first!
    install_brew()

    # Update environment variables such as PATH, DL_LOAD_PATH, etc...
    update_env()
end

function install_brew()
    # Ensure brew_prefix exists
    mkpath(brew_prefix)

    # Make sure brew isn't already installed
    if !isexecutable( brew )
        # Clone brew into brew_prefix
        Base.info("Cloning brew from $BREW_URL")
        try Git.run(`clone $BREW_URL -b $BREW_BRANCH --depth 1 $brew_prefix`)
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
end

function update()
    Git.run(`fetch origin`, dir=brew_prefix)
    Git.run(`reset --hard origin/$BREW_BRANCH`, dir=brew_prefix)
    Git.run(`fetch origin`, dir=tappath)
    Git.run(`reset --hard origin/master`, dir=tappath)
    upgrade()
end

# Update environment variables so we can natively call brew, otool, etc...
function update_env()
    if length(Base.search(ENV["PATH"], joinpath(brew_prefix, "bin"))) == 0
        ENV["PATH"] = "$(realpath(joinpath(brew_prefix, "bin"))):$(joinpath(brew_prefix, "sbin")):$(ENV["PATH"])"
    end

    if !(joinpath(brew_prefix,"lib") in DL_LOAD_PATH)
        push!(DL_LOAD_PATH, joinpath(brew_prefix, "lib") )
    end

    # We need to set our own, private, cache directory so that we don't conflict with
    # user-maintained Homebrew installations, and multiple users can use it at once
    ENV["HOMEBREW_CACHE"] = joinpath(ENV["HOME"],"Library/Caches/Homebrew.jl/")
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

# List all installed packages as a list of BrewPkg items
function list()
    brew_list = readchomp(`$brew list --versions`)
    if length(brew_list) != 0
        [BrewPkg(split(f)) for f in split(brew_list,"\n")]
    else
        []
    end
end

# List all outdated packages as a list of names
function outdated()
    brew_outdated = readchomp(`brew outdated`)
    if length(brew_outdated) != 0
        split(brew_outdated,"\n")
    else
        []
    end
end

function upgrade()
    # We have to manually upgrade each package, as `brew upgrade` will pull from mxcl/master
    for f in outdated()
        run(`$brew rm staticfloat/juliadeps/$f`)
        run(`$brew install staticfloat/juliadeps/$f`)
    end
end

# Print out info for a specific package
function info(pkg)
    readchomp(`$brew info staticfloat/juliadeps/$pkg`)
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
            run(`$brew unlink --quiet $pkg`)
        end
        run(`$brew install staticfloat/juliadeps/$pkg`)
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
    run(`$brew rm --force $pkg`)
end

function rm(pkg::BrewPkg)
    rm(pkg.name)
end

# Include our own, personal bindeps integration stuff
include("bindeps.jl")

init()
end # module

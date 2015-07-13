module Homebrew

import Base: show
if VERSION >= v"0.3.0-"
    import Base: Pkg.Git
else
    import Base: Git
end
using JSON
using Compat

# Homebrew prefix
const brew_prefix = Pkg.dir("Homebrew", "deps", "usr")
const brew = joinpath(brew_prefix,"bin","brew")
const tappath = joinpath(brew_prefix,"Library","Taps","staticfloat","homebrew-juliadeps")

const BREW_URL = "https://github.com/Homebrew/homebrew.git"
const BREW_BRANCH = "master"
const BOTTLE_SERVER = "https://juliabottles.s3.amazonaws.com"

const DL_LOAD_PATH = VERSION >= v"0.4.0-dev+3844" ? Libdl.DL_LOAD_PATH : Base.DL_LOAD_PATH


function init()
    # Let's see if Homebrew is installed.  If not, let's do that first!
    install_brew()

    # Update environment variables such as PATH, DL_LOAD_PATH, etc...
    update_env()
end

# Ignore STDERR
function quiet_run(cmd::Cmd)
    run(cmd, (STDIN, STDOUT, DevNull), false, false)
end

# Ignore STDOUT and STDERR
function really_quiet_run(cmd::Cmd)
    run(cmd, (STDIN, DevNull, DevNull), false, false)
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

    # Make sure we're on the right repo.  If not, clear it out!
    if Git.readchomp(`config remote.origin.url`, dir=brew_prefix) != BREW_URL
        Git.run(`config remote.origin.url $BREW_URL`, dir=brew_prefix)
        Git.run(`config remote.origin.fetch +refs/heads/master:refs/remotes/origin/master`, dir=brew_prefix)
        Git.run(`fetch origin`, dir=brew_prefix)
        Git.run(`reset --hard origin/$BREW_BRANCH`, dir=brew_prefix)
    end

    # Remove old tappath if it exists
    old_tappath = joinpath(brew_prefix,"Library","Taps","staticfloat-juliadeps")
    if isdir(old_tappath)
        if VERSION >= v"0.3.0-rc1"
            Base.rm(old_tappath, recursive=true)
        else
            run(`rm -rf $(old_tappath)`)
        end
        quiet_run(`$brew prune`)
    end


    if !isexecutable(joinpath(brew_prefix,"bin","otool"))
        # Download/install packaged install_name_tools
        try
            pipe(run(`curl --location $BOTTLE_SERVER/cctools_bundle.tar.gz`, `tar xz -C $(joinpath(brew_prefix,"bin"))`))
        catch
            warn("Could not download/extract $BOTTLE_SERVER/cctools_bundle.tar.gz into $(joinpath(brew_prefix,"bin"))!")
            rethrow()
        end
    end

    if !isdir(tappath)
        # Tap staticfloat/juliadeps
        try
            quiet_run(`$brew tap staticfloat/juliadeps`)
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
    version::VersionNumber
    version_str::ASCIIString
    bottled::Bool
    cellar::ASCIIString

    BrewPkg(n, v, vs, b) = new(n, v, vs, b)
end

function show(io::IO, b::BrewPkg)
    write(io, "$(b.name): $(b.version) $(b.bottled ? "(bottled)" : "")")
end

function prefix()
    brew_prefix
end

# Get the prefix of a given package's latest version
function prefix(name::AbstractString)
    cellar_path = joinpath(brew_prefix, "Cellar", name)
    version_str = info(name).version_str
    return joinpath(brew_prefix, "Cellar", name, version_str)
end

# If we pass in a BrewPkg, just sub out to running it on the name
function prefix(pkg::BrewPkg)
    prefix(pkg.name)
end

# Convert brew's much more lax versioning into something that we can handle
function make_version(name::AbstractString, vers_str::AbstractString)
    # Most of the time we fail due to weird stuff at the end; let's cut it off until it works!
    failing = true
    vers = nothing
    idx = length(vers_str)
    while failing && idx > 0
        try
            vers = convert(VersionNumber, vers_str[1:idx])
            failing = false
        catch
            idx -= 1
        end
    end

    if idx != 0
        # If there's some that we chopped off, see how much we can restore via +
        if idx < length(vers_str)
            idx_add = idx+2
            passing = true
            while passing && idx_add <= length(vers_str)
                try
                    vers = convert(VersionNumber, "$(vers_str[1:idx])+$(vers_str[idx+2:idx_add])")
                    idx_add += 1
                catch
                    passing = false
                end
            end
        end
    else
        # Special-case things we know how to deal with here
        if name == "x264"
            vers = convert(VersionNumber, vers_str[2:end])
        else
            warn("Brew is feeding us a weird version string for $(name): $(vers_str)")
            warn("Please report this at https://github.com/JuliaLang/Homebrew.jl")
            vers = v"1.0"
        end
    end

    return vers
end

# List all installed packages as a list of BrewPkg items
function list()
    brew_list = readchomp(`$brew list --versions`)
    if length(brew_list) != 0
        pkgs = BrewPkg[]
        for f in split(brew_list,"\n")
            name = split(f, " ")[1]
            vers = make_version(name, split(f, " ")[2])
            vers_str = split(f, " ")[2]
            push!(pkgs, BrewPkg(name, vers, vers_str, false))
        end
        return pkgs
    else
        BrewPkg[]
    end
end

function find(name::ASCIIString, pkgs::Vector{BrewPkg})
    for p in pkgs
        if p.name == name
            return p
        end
    end
    return nothing
end

# List all outdated packages as a list of BrewPkg's
function outdated()
    outdated_pkgs = BrewPkg[]
    brew_outdated = readchomp(`$brew outdated`)
    if length(brew_outdated) == 0
        return outdated_pkgs
    end

    installed_packages = list()

    # For each package that brew outdated gives us
    for f in split(brew_outdated,"\n")
        # Get information about it
        pkg = info(f)

        # Check it against each package we have installed
        inst_pkg = find(pkg.name, installed_packages)

        # If this package isn't installed, or is and is actually a lower version
        if inst_pkg == nothing || (inst_pkg.version < pkg.version)
            push!(outdated_pkgs, pkg)
        end
    end
    return outdated_pkgs
end

function upgrade()
    # We have to manually upgrade each package, as `brew upgrade` will pull from mxcl/master
    for pkg in outdated()
        rm(pkg)
        add(pkg)
    end
end

# Get info for a specific package
function info(pkg)
    json_str = ""
    cd(tappath) do
        try
            if isfile( "$pkg.rb" )
                json_str = readchomp(`$brew info --json=v1 staticfloat/juliadeps/$pkg`)
            else
                json_str = readchomp(`$brew info --json=v1 $pkg`)
            end
        catch
            throw(ArgumentError("Cannot find formula for $(pkg)!"))
        end
    end

    if length(json_str) != 0
        obj = JSON.parse(json_str)

        if length(obj) != 0
            obj = obj[1]
            # First, get name and version
            name = obj["name"]
            version = make_version(name, obj["versions"]["stable"])
            version_str = obj["versions"]["stable"]
            if obj["revision"] > 0
                version_str *= "_$(obj["revision"])"
            end
            bottled = obj["versions"]["bottle"]

            # If we actually have a keg, return whether it was poured
            if !isempty(obj["installed"])
                bottled = obj["installed"][1]["poured_from_bottle"]
            end

            # Then, return a BrewPkg!
            return BrewPkg(name, version, version_str, bottled)
        else
            throw(ArgumentError("Cannot parse info for $(pkg)!"))
        end
    else
        throw(ArgumentError("brew didn't give us any info for $(pkg)!"))
    end
end

# Install a package
function add(pkg::AbstractString)
    # First, check to make sure we don't already have this version installed

    cd(tappath) do
        # First, unlink any previous versions of this package
        if linked( pkg )
            run(`$brew unlink --quiet $pkg`)
        end
        # If we've got it in our tap, install it
        if isfile( "$pkg.rb" )
            run(`$brew install --force-bottle staticfloat/juliadeps/$pkg`)
        else
            # If not, try to install it from Homebrew
            run(`$brew install --force-bottle $pkg`)
        end

        # Finally, if we need to, link it in
        quiet_run(`$brew link $pkg`)
    end
end

function add(pkg::BrewPkg)
    add(pkg.name)
end


function installed(pkg::AbstractString)
    isdir(joinpath(brew_prefix,"Cellar",pkg))
end

function installed(pkg::BrewPkg)
    installed(pkg.name)
end

function linked(pkg::AbstractString)
    return islink(joinpath(brew_prefix,"Library","LinkedKegs",pkg))
end

function linked(pkg::BrewPkg)
    return linked(pkg.name)
end

function rm(pkg::AbstractString)
    run(`$brew rm --force $pkg`)
end

function rm(pkg::BrewPkg)
    rm(pkg.name)
end

# Include our own, personal bindeps integration stuff
include("bindeps.jl")

init()
end # module

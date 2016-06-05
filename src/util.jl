# This file contains various utility functions that don't belong anywhere else

"""
update_env()

Updates environment variables PATH and HOMEBREW_CACHE, and modifies DL_LOAD_PATH
to point to our Homebrew installation, allowing us to use things inside of Homebrew
transparently.  This allows BinDeps to find the binaries during Pkg.build() time,
then writing the absolute path into `deps/deps.jl`.  Because the paths are written
into `deps/deps.jl`, packages do not need to load in the entire Homebrew package
just to find their dependencies.

HOMEBREW_CACHE stores our bottle download cache in a separate place, separating
ourselves from other Homebrew installations so we don't conflict with anyone
"""
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

    # If we have `git` installed from Homebrew, add its environment variables
    if isfile(joinpath(brew_prefix,"bin","git"))
        ENV["GIT_EXEC_PATH"] = joinpath(brew_prefix,"opt","git","libexec","git-core")
        ENV["GIT_TEMPLATE_DIR"] = joinpath(brew_prefix,"opt","git","share","git-core")
    end
    return
end


"""
make_version(name::String, vers_str::String)

Massage a version string from Homebrew into a valid Julia `VersionNumber` as
best we can.  Homebrew will occasionally give us version numbers such as
"1.0.2h_1", which doesn't map cleanly to a SemVer versioning system.  This
function does its best to fit things into SemVer, and then tacks everything else
onto the end as a `+` extension, e.g. the previous example maps to v"1.0.2-h+1".

Also special-cases some version numbers that we know are bizarre such as the
x264 formula, which uses dates as version numbers.
"""
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


"""
normalize_name(name::String)

Given package `name`, checks if `name` has a tap on its front and if so, taps it.
If no tap is present, checks if the `staticfloat/juliadeps` tap should be.

Returns the normalized name.
"""
function normalize_name(name::String)
    # First, does this name have a tap in front of it?
    tapname = dirname(name)

    if isempty(tapname)
        # If not, auto-detect whether we need to add staticfloat/juliadeps to the front
        if tap_overrides(name)
            name = "staticfloat/juliadeps/$name"
        end
    else
        # If we do have a tap in front of us, let's make sure it's tapped
        tap(tapname)
    end

    return name
end


"""
add_flags(cmd::String, flags::Dict{String,Bool})

Given a mapping of flags to Bools, return [cmd, flag1, flag2...] if the
respective Bools are true.  Useful for adding `--verbose` and `--force` flags
onto the end of commands
"""
function add_flags(cmd::Cmd, flags::Dict{Cmd,Bool})
    for flag in keys(flags)
        if flags[flag]
            cmd = `$cmd $flag`
        end
    end
    return cmd
end


"""
download_and_unpack(url::String, target_dir::String)

Download a tarball from `url` and unpack it into `target_dir`.
"""
function download_and_unpack(url::String, target_dir::String; strip=0)
    @compat run(pipeline(`curl -# -L $url`,
                         `tar xz -m --strip 1 -C $target_dir`))
end

"""
clt_installed()

Checks whether the command-line tools are installed, as reported by xcode-select
"""
function clt_installed()
    try
        @compat !isempty(readchomp(pipeline(`/usr/bin/xcode-select -print-path`, stderr=DevNull)))
    catch
        return false
    end
end

"""
git_installed()

Checks whether `git` is truly installed or not, dealing with stubs in /usr/bin
"""
function git_installed()
    gitpath = readchomp(`which git`)

    # If there is no `git` executable at all, fail
    if isempty(gitpath)
        return false
    end

    # If we have a git from the CLT location, but the CLT isn't installed, fail
    if gitpath == "/usr/bin/git" && !clt_installed()
        return false
    end

    # If we made it through the gauntlet, succeed!
    return true
end

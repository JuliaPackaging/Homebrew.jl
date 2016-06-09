# This file contains various utility functions that don't belong anywhere else

"""
update_env()

Updates environment variables PATH and HOMEBREW_CACHE, and modifies DL_LOAD_PATH
to point to our Homebrew installation, allowing us to use things inside of
Homebrew transparently. This causes BinDeps to find the binaries during
Pkg.build() time, writing the absolute path into `deps/deps.jl`.  Because the
paths are written into `deps/deps.jl`, packages do not need to load in the entire
Homebrew package just to find their dependencies.

HOMEBREW_CACHE stores our bottle download cache in a separate place, separating
ourselves from other Homebrew installations so we don't conflict with anyone
"""
function update_env()
    if isempty(Base.search(ENV["PATH"], joinpath(brew_prefix, "bin")))
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
normalize_name(name::AbstractString)

Given package `name`, checks if `name` has a tap on its front and if so, taps it.
If no tap is present, checks if the `staticfloat/juliadeps` tap should be.

Returns the normalized name.
"""
function normalize_name(name::AbstractString)
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
add_flags(cmd::AbstractString, flags::Dict{String,Bool})

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
download_and_unpack(url::AbstractString, target_dir::AbstractString)

Download a tarball from `url` and unpack it into `target_dir`.
"""
function download_and_unpack(url::AbstractString, target_dir::AbstractString; strip=0)
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

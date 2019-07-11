# This file contains all functions that either do not directly interface with `brew`
# or peek into the internals of Homebrew a bit, such as `install_brew()` which
# installs Homebrew using Git, `tap_exists()` which presupposes knowledge of the
# internal layout of Taps, and `installed()` which presupposed knowledge of the
# location of files within the Cellar

# This is the tap that contains our manually-curated overrides
const tapname = "staticfloat/juliadeps"
const tappath = joinpath(brew_prefix,"Library","Taps","staticfloat","homebrew-juliadeps")

# This is the tap that will contain our automatically-translated overrides
const auto_tapname = "staticfloat/juliatranslated"
const auto_tappath = joinpath(brew_prefix,"Library","Taps","staticfloat","homebrew-juliatranslated")

# Where we download brew from
const BREW_URL = "https://github.com/Homebrew/brew"
const BREW_BRANCH = "master"
const BREW_STABLE_SHA = "2b83463091513826127c14acae81a7c354dfce69"

"""
`install_brew()`

Ensures that Homebrew is installed as desired, that our basic Taps are available
and that we have whatever binary tools we need, such as `install_name_tool`
"""
function install_brew()
    # Ensure brew_prefix exists
    if !isdir(brew_prefix) || !isfile(joinpath(brew_prefix,"bin","brew"))
        try
            mkdir(brew_prefix)
        catch
        end

        try
            @info("Downloading brew...")
            run(pipeline(`curl -\# -L $BREW_URL/tarball/$BREW_BRANCH`,
                                 `tar xz -m --strip 1 -C $brew_prefix`))
        catch
            @warn("Could not download/extract $BREW_URL/tarball/$BREW_BRANCH into $(brew_prefix)!")
            rethrow()
        end
        
        cd(brew_prefix) do
            try
                git(`fetch --unshallow`)
            catch
            end
        end
    end

    # Tap homebrew/core, always and forever
    tap("homebrew/core")

    # Tap our own "overrides" taps
    tap("staticfloat/juliadeps")
    tap("staticfloat/juliatranslated")

    if !clt_installed() && !installed("cctools")
        # If we don't have the command-line tools installed, then let's grab
        # cctools, as we need that to install bottles that need relocation
        add("cctools")
    end

    if !git_installed() && !installed("git")
        # If we don't have a git available, install it now
        add("git")
    end

    # Update the environment before running update()
    update_env()

    # Update immediately so that we get onto our "stable" tag
    update(verbose=true)

    return nothing
end

"""
`tap_exists(tap_name::AbstractString)`

Check to see if a tap called `tap_name` (ex: `"staticfloat/juliadeps"`) exists
"""
function tap_exists(tap_name::AbstractString)
    path = joinpath(brew_prefix,"Library","Taps", dirname(tap_name), "homebrew-$(basename(tap_name))")
    return isdir(path)
end


"""
`installed(pkg::Union{AbstractString,BrewPkg})`

Return true if the given package `pkg` is a directory in the Cellar, showing
that it has been installed (but possibly not linked, see `linked()`)
"""
function installed(pkg::StringOrPkg) end

function installed(name::AbstractString)
    isdir(joinpath(brew_prefix,"Cellar",basename(name)))
end

function installed(pkg::BrewPkg)
    installed(pkg.name)
end


"""
`linked(pkg::Union{AbstractString,BrewPkg})`

Returns true if the given package `pkg` is linked to LinkedKegs, signifying
all files installed by this package have been linked into the global prefix.
"""
function linked(pkg::StringOrPkg) end

function linked(name::AbstractString)
    return islink(joinpath(brew_prefix,"var","homebrew","linked",basename(name)))
end

function linked(pkg::BrewPkg)
    return linked(pkg.name)
end


"""
`formula_path(pkg::Union{AbstractString,BrewPkg})`

Returns the absolute path on-disk of the given package `pkg`.
"""
function formula_path(pkg::StringOrPkg) end

function formula_path(name::AbstractString)
    path, tap_path = formula_tap(name)

    if isempty(tap_path)
        return joinpath(brew_prefix, "Library", "Taps", "homebrew", "homebrew-core", "Formula", "$path.rb")
    else
        # Insert the "homebrew-" that exists in all taps
        tap_path = "$(dirname(tap_path))/homebrew-$(basename(tap_path))"
        return joinpath(brew_prefix, "Library", "Taps", tap_path, "$path.rb")
    end
end

function formula_path(pkg::BrewPkg)
    return formula_path(fullname(pkg))
end


"""
`update_tag(;verbose::Bool = false)`

We maintain our own "stable" tag that overrides Homebrew so that we can
update at our own pace along with them.  Make sure to call `update_env()`
before calling this, as calling our `git` doesn't work properly otherwise.
"""
function update_tag(;verbose::Bool=false)
    global BREW_STABLE_SHA, brew_prefix

    # If a recent enough version of git is not installed, then install our own
    # This is necessary because some people do not have git installed but already
    # have Homebrew installed, and the check up above during install_brew()
    # doesn't run every time
    if !git_installed()
        add("git")
    end

    if verbose
        git = cmd -> run(`git $cmd`)
    else
        git = cmd -> run(pipeline(`git $cmd`, stdout=devnull, stderr=devnull))
    end

    cd(brew_prefix) do
        try
            git(`tag -d 9.9.9`)
        catch
        end
        git(`tag 9.9.9 $BREW_STABLE_SHA`)
        git(`checkout 9.9.9`)
    end
    return nothing
end

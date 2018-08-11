module Homebrew

import Base: show
using Unicode, JSON, Libdl, InteractiveUtils

# Find homebrew installation prefix
const brew_prefix = abspath(joinpath(dirname(@__FILE__),"..","deps", "usr"))
const brew_exe = joinpath(brew_prefix,"bin","brew")

# Types and show() overrides, etc..
include("types.jl")

# Utilities
include("util.jl")

# The public API that uses Homebrew like a blackbox, only through the `brew` script
include("API.jl")

# The private API that peeks into the internals of Homebrew a bit
include("private_API.jl")
include("translation.jl")

# Include our own, personal bindeps integration stuff
include("bindeps_integration.jl")


"""
`__init__()`

Initialization function.  Calls `install_brew()` to ensure that everything we
need is downloaded/installed, then calls `update_env()` to set the environment
properly so that packages being installed can find their binaries.
"""
function __init__()
    if Sys.isapple()
        # Let's see if Homebrew is installed.  If not, let's do that first!
        (isdir(brew_prefix) && isdir(tappath)) || install_brew()

        # Update environment variables such as PATH, DL_LOAD_PATH, etc...
        update_env()
    else
        # change this to an error in future
        @warn("""
Homebrew.jl can only be used on Apple macOS. Suggested usage is

    @static if Sys.isapple()
        using Homebrew
        # Homebrew specific code goes here
    end
""")
    end
end


end # module

module Starlight

using Reexport
@reexport using Base: Semaphore, acquire, release, ReentrantLock, lock, unlock
@reexport using DataStructures: Queue, enqueue!, dequeue!
@reexport using DataFrames
@reexport using YAML
@reexport using Colors, ColorTypes, ColorVectorSpace
@reexport using SimpleDirectMediaLayer
@reexport using SimpleDirectMediaLayer.LibSDL2

export handleMessage, sendMessage, sendMessageTo, listenFor, listenForFrom, dispatchMessage
export System, App, awake!, shutdown!, system!, on, off, cat
export app, cfg, str_to_clrnt, get_env_int, get_env_str, get_env_clr, get_env_flt, get_env_bl

import DotEnv
cfg = DotEnv.config()

str_to_clrnt(s) = parse(Colorant, s)
get_env_int(n, d) = parse(Int, get(ENV, n, string(d)))
get_env_str(n, d) = get(ENV, n, string(d)) # no parse necessary since all env variables are strings by default
get_env_clr(n, d) = str_to_clrnt(get(ENV, n, string(d)))
get_env_flt(n, d) = parse(Float64, get(ENV, n, string(d)))
get_env_bl(n, d) = parse(Bool, get(ENV, n, string(d)))

DEFAULT_PRIORITY = get_env_int("DEFAULT_PRIORITY", 0)
MQUEUE_SIZE = get_env_int("MQUEUE_SIZE", 1000)

const listeners = Dict{DataType, Set{Any}}()
const messages = Queue{Any}()
const from = Dict{Any, Dict{DataType, Set{Any}}}()

const slot_available = Semaphore(MQUEUE_SIZE)
const msg_ready = Semaphore(MQUEUE_SIZE)
const mqueue_lock = Semaphore(1)
const entity_lock = Semaphore(1)
const listener_lock = Semaphore(1)

for i in 1:MQUEUE_SIZE
  acquire(msg_ready)
end

handleMessage(l, m) = nothing

function sendMessage(m)
  # drop if no one's listening
  if haskey(listeners, typeof(m))
    acquire(slot_available)
    acquire(mqueue_lock)
    enqueue!(messages, m)
    release(mqueue_lock)
    release(msg_ready)
  end
end

# allow direct invocation of message handlers
# for cases when we know all the recipients in
# advance and there would otherwise be too many
# listeners (i.e. collision notifications)
function sendMessageTo(m, t)
  for to in t
    handleMessage(to, m)
  end
end

function add_listener!(e::Any, d::DataType)
  if !haskey(listeners, d) listeners[d] = Set{Any}() end
  push!(listeners[d], e)
end

function listenFor(e::Any, d::DataType)
  acquire(listener_lock)
  add_listener!(e, d)
  release(listener_lock)
end

# used in cases where we care about the sender
# as well as the message
function listenForFrom(e::Any, d::DataType, e2::Any)
  acquire(listener_lock)
  add_listener!(e, d)
  if !haskey(from, e) from[e] = Dict{DataType, Set{Any}}() end
  if !haskey(from[e], d) from[e][d] = Set{Any}() end
  push!(from[e][d], e2)
  release(listener_lock)
end

# TODO implement "unlisten" function and test
# NOTE this would only ever be used by the ECS
# when removing an entity, it's too much to ask
# users to write finalizers that do this, i.e.
# this is not terribly important right now

# uses single argument to support
# being called as a job by a Clock,
# see Clock.jl for that interface
function dispatchMessage(arg)
  acquire(msg_ready)
  acquire(mqueue_lock) # NOTE this lock guarantees that messages are fully processed in the order they are received
  m = dequeue!(messages)
  d = typeof(m)
  @debug "dequeued message $(m) of type $(d)"
  if haskey(listeners, d)
    # Threads.@threads doesn't work on raw sets
    # because it needs to use indexing to split
    # up memory, i work around it this way
    Threads.@threads for l in Vector([listeners[d]...])
      # only call handler if the sender is
      # being listened for, i.e. matches one
      # the recipient cares about, or the
      # recipient doesn't care
      if haskey(from, l) && haskey(from[l], d)
        if !hasproperty(m, :from) || m.from ∉ from[l][d]
          continue
        end
      end
      handleMessage(l, m)
    end
  end
  release(mqueue_lock)
  release(slot_available)
end

abstract type System end

# these functions are supposed to return
# whether a value indicating whether the 
# system is still running or not, except
# for App where it returns a vector of
# booleans indicating whether each system
# is still running
awake!(s::System) = true
shutdown!(s::System) = false

include("Clock.jl")
include("ECS.jl")
include("SDL.jl")
include("Scene.jl")

mutable struct App <: System
  systems::Dict{DataType, System}
  running::Vector{Bool}
  function App(appf::String="")
    # singleton pattern from Tom Kwong's book
    global app
    global app_lock
    lock(app_lock)
    try 
      if !isassigned(app)

        a = new(Dict(), Vector{Bool}())
        
        system!(a, clk)
        system!(a, ecs)
        system!(a, sdl)
        system!(a, scn)
      
        a.running = [false for s in keys(a.systems)]

        app[] = finalizer(shutdown!, a)

      end

      # check environment variables first
      # clock
      clk.freq = get_env_flt("CLOCK_FREQ", 0.01667) # 60hz
      clk.fire_sec = get_env_bl("CLOCK_FIRE_SEC", false)
      clk.fire_msec = get_env_bl("CLOCK_FIRE_MSEC", false)
      clk.fire_usec = get_env_bl("CLOCK_FIRE_USEC", false)
      clk.fire_nsec = get_env_bl("CLOCK_FIRE_NSEC", false)
      # sdl
      sdl.bgrd = to_ARGB(get_env_clr("BACKGROUND_COLOR", "gray"))
      sdl.wdth = get_env_int("WINDOW_WIDTH", 800)
      sdl.hght = get_env_int("WINDOW_HEIGHT", 450)
      sdl.ttl = get_env_str("TITLE", "Starlight.jl")

      # ...then override from file if needed.
      # also, making all this separate from instance initialization
      # means that sequential env/file loads will merge and/or
      # overwrite results with each other on the global app.
      if isfile(appf)
        yml = YAML.load_file(appf) # may support other file types in the future
        if haskey(yml, "clock") && yml["clock"] isa Dict
          clkdict = yml["clock"]
          if haskey(clkdict, "fire_sec") clk.fire_sec = clkdict["fire_sec"] end
          if haskey(clkdict, "fire_msec") clk.fire_msec = clkdict["fire_msec"] end
          if haskey(clkdict, "fire_usec") clk.fire_usec = clkdict["fire_usec"] end
          if haskey(clkdict, "fire_nsec") clk.fire_nsec = clkdict["fire_nsec"] end
          if haskey(clkdict, "freq") clk.freq = clkdict["freq"] end
        end
        if haskey(yml, "sdl") && yml["sdl"] isa Dict
          sdldict = yml["sdl"]
          if haskey(sdldict, "background_color") sdl.bgrd = str_to_clrnt(sdldict["background_color"]) end
          if haskey(sdldict, "window_height") sdl.hght = sdldict["window_height"] end
          if haskey(sdldict, "window_width") sdl.wdth = sdldict["window_width"] end
          if haskey(sdldict, "title") sdl.ttl = sdldict["title"] end
        end
      end
    catch e
      rethrow()
    finally
      unlock(app_lock)
      return app[]
    end
  end
end

const app = Ref{App}()
const app_lock = ReentrantLock()

on(a::App) = all(a.running)
off(a::App) = all(!r for r in a.running)
# shrodinger's app is neither on nor off, 
# i.e. some system is not synchronized with the others
cat(a::App) = !on(a) && !off(a)

system!(a::App, s::System) = a.systems[typeof(s)] = s
# note that if running from a script the app will
# still exit when julia exits, it will never block.
# figuring out whether/how to keep it alive is
# on the user.
function awake!(a::App)
  if !on(a)
    job!(a.systems[Clock], dispatchMessage) # this could be parallelized if not for mqueue_lock
    a.running = map(awake!, values(a.systems))
  end
  return a.running
end
function shutdown!(a::App)
  if !off(a)
    a.running = map(shutdown!, values(a.systems))
  end
  return a.running
end

awake!() = awake!(app[])
shutdown!() = shutdown!(app[])

end
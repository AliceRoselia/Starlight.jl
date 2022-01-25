module Starlight

using Base: Semaphore, acquire, release
using DataStructures
using YAML
using SimpleDirectMediaLayer
using SimpleDirectMediaLayer.LibSDL2

export priority, id, handleMessage, sendMessage, listenFor, dispatchMessages
export System, App, awake, shutdown, add_system!
export Clock, RT_SEC, RT_MSEC, RT_USEC, RT_NSEC, TICK, SLEEP_TIME
export nsleep, usleep, msleep, ssleep, tick, add_job!

import DotEnv
cfg = DotEnv.config()

DEFAULT_PRIORITY = parse(Int, get(ENV, "DEFAULT_PRIORITY", 0))
DEFAULT_ID = parse(Int, get(ENV, "DEFAULT_ID", 0))
DISPATCHER_BATCH_SIZE = parse(Int, get(ENV, "DISPATCHER_BATCH_SIZE", 1))
MQUEUE_SIZE = parse(Int, get(ENV, "MQUEUE_SIZE", 1000))

entities = Dict{Int, Any}()
listeners = Dict{DataType, Vector{Any}}()
messages = PriorityQueue{Any, Int}()

slot_available = Semaphore(MQUEUE_SIZE)
msg_ready = Semaphore(MQUEUE_SIZE)
mqueue_lock = Semaphore(1)
entity_lock = Semaphore(1)
listener_lock = Semaphore(1)

for i in 1:MQUEUE_SIZE
  acquire(msg_ready)
end

function priority(e)
  (hasproperty(e, :priority)) ? e.priority : DEFAULT_PRIORITY
end

function id(e)
  (hasproperty(e, :id)) ? e.id : DEFAULT_ID
end

function handleMessage(l, m)
  nothing
end

function sendMessage(m)
  acquire(slot_available)
  acquire(mqueue_lock)
  enqueue!(messages, m, priority(m))
  release(mqueue_lock)
  release(msg_ready)
end

function listenFor(d::DataType, e)
  acquire(listener_lock)
  if !haskey(listeners, d) listeners[d] = Vector{Any}() end
  push!(listeners[d], e)
  release(listener_lock)
end

function dispatchMessages(n)
  n = min(n, length(messages))
  for i in 1:n
    acquire(msg_ready)
    acquire(mqueue_lock)
    m = dequeue_pair!(messages)
    for l in listeners[typeof(m)]
      handleMessage(l, m)
    end
    release(mqueue_lock)
    release(slot_available)
  end
end

abstract type System end
abstract type Event end

awake(s::System) = nothing
shutdown(s::System) = nothing

mutable struct App <: System
  systems::Vector{System}
  function App(ymlf::String="")
    a = new([])
    c = Clock()
    add_system!(a, c)
    add_job!(c, dispatchMessages, DISPATCHER_BATCH_SIZE)
  
    if isfile(ymlf)
      yml = YAML.load_file(ymlf)
      if haskey(yml, "clock") && yml["clock"] isa Dict
        clk = yml["clock"]
        if haskey(clk, "fire_sec") c.fire_sec = clk["fire_sec"] end
        if haskey(clk, "fire_msec") c.fire_msec = clk["fire_msec"] end
        if haskey(clk, "fire_usec") c.fire_usec = clk["fire_usec"] end
        if haskey(clk, "fire_nsec") c.fire_nsec = clk["fire_nsec"] end
        if haskey(clk, "freq") c.freq = clk["freq"] end
      end
    end
  
    return a
  end
end

add_system!(a::App, s::System) = push!(a.systems, s) 
awake(a::App) = map(awake, a.systems)
shutdown(a::App) = map(shutdown, a.systems)

include("Clock.jl")
include("Rendering.jl")
include("Physics.jl")
include("AI.jl")
include("Audio.jl")
include("Scene.jl")
include("Input.jl")

end
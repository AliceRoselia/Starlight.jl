export Entity, update!
export ECS, XYZ, accumulate_XYZ, get_entity_row, get_entity_by_id
export get_entity_row_by_id, get_df_row_prop, set_df_row_prop!
export ECSIterator, ECSIteratorState, Level
export Root, instantiate!, destroy!
export ecs, lvl

abstract type Entity <: System end

awake!(e::Entity) = true
shutdown!(e::Entity) = false
update!(e, Δ) = nothing

# magic symbols that getproperty and setproperty! (and end users) care about
const ENT = :ent
const TYPE = :type
const ID = :id
const PARENT = :parent
const CHILDREN = :children
const POSITION = :pos
const ROTATION = :rot
const ABSOLUTE_POSITION = :abs_pos
const ABSOLUTE_ROTATION = :abs_rot
const ACTIVE = :active
const HIDDEN = :hidden
const PROPS = :props

# position, rotation, velocity, acceleration, whatever
mutable struct XYZ
  x::Number
  y::Number
  z::Number
  XYZ(x=0, y=0, z=0) = new(x, y, z)
end

import Base.+, Base.-, Base.*, Base.÷, Base./, Base.%
+(a::XYZ, b::XYZ) = XYZ(a.x+b.x,a.y+b.y,a.z+b.z)
-(a::XYZ, b::XYZ) = XYZ(a.x-b.x,a.y-b.y,a.z-b.z)
*(a::XYZ, b::Number) = XYZ(a.x*b,a.y*b,a.z*b)
÷(a::XYZ, b::Number) = XYZ(a.x÷b,a.y÷b,a.z÷b)
/(a::XYZ, b::Number) = XYZ(a.x/b,a.y/b,a.z/b)
%(a::XYZ, b::Number) = XYZ(a.x%b,a.y%b,a.z%b)

# columns of the in-memory database
const components = Dict(
  ENT=>Entity,
  TYPE=>DataType,
  ID=>Int,
  PARENT=>Int,
  CHILDREN=>Set{Int},
  POSITION=>XYZ,
  ROTATION=>XYZ,
  ACTIVE=>Bool,
  HIDDEN=>Bool,
  PROPS=>Dict{Symbol, Any}
)

mutable struct ECS <: System
  df::DataFrame
  awoken::Bool
  function ECS()
    df = DataFrame(
      NamedTuple{Tuple(keys(components))}(
        t[] for t in values(components)
      ))
    return new(df, false)
  end
end

const ecs = ECS()

# internally uses Base.getproperty directly so
# as to not break if the symbol values change
get_entity_row(ent::Entity) = @view ecs.df[getproperty(ecs.df, ENT) .== [ent], :]
get_entity_by_id(id::Int) = ecs.df[getproperty(ecs.df, ID) .== [id], ENT][1]
get_entity_row_by_id(id::Int) = @view ecs.df[getproperty(ecs.df, ID) .== [id], :]
get_df_row_prop(r, s) = r[!, s][1]
set_df_row_prop!(r, s, x) = r[!, s][1] = x

function Base.propertynames(ent::Entity)
  return (
    ENT,
    TYPE,
    ID,
    CHILDREN,
    PARENT,
    POSITION,
    ROTATION,
    ABSOLUTE_POSITION,
    ABSOLUTE_ROTATION,
    ACTIVE,
    HIDDEN,
    PROPS,
    [n for n in keys(getproperty(ent, PROPS))]...
  )
end

function Base.hasproperty(ent::Entity, s::Symbol)
  return s in Base.propertynames(ent)
end

function accumulate_XYZ(r, s)
  acc = XYZ()
  while true
    inc = get_df_row_prop(r, s)
    acc += inc
    r = get_entity_row_by_id(get_df_row_prop(r, PARENT))
    get_df_row_prop(r, PARENT) != 0 || return acc
  end
end

function Base.getproperty(ent::Entity, s::Symbol)
  e = get_entity_row(ent)
  if s == ABSOLUTE_POSITION return accumulate_XYZ(e, POSITION)
  elseif s == ABSOLUTE_ROTATION return accumulate_XYZ(e, ROTATION)
  elseif s in keys(components) return get_df_row_prop(e, s)
  elseif s in keys(get_df_row_prop(e, PROPS)) return get_df_row_prop(e, PROPS)[s]
  else return getfield(ent, s)
  end
end

const ecs_lock = ReentrantLock()

function Base.setproperty!(ent::Entity, s::Symbol, x)
  e = get_entity_row(ent)
  if s in [
    ENT, # immutable
    TYPE, # automatically set
    ID, # automatically set
    ABSOLUTE_POSITION, # computed
    ABSOLUTE_ROTATION # computed
  ]
    error("cannot set property $(s) on Entity")
  end

  lock(ecs_lock)
  if s == PARENT
    par = get_entity_by_id(get_df_row_prop(e, PARENT))
    push!(getproperty(par, CHILDREN), get_df_row_prop(e, ID))
  elseif s in keys(components) && s != PROPS
    set_df_row_prop!(e, s, x)
  else
    get_df_row_prop(e, PROPS)[s] = x
  end
  unlock(ecs_lock)
end

Base.length(e::ECS) = size(e.df)[1]

# can define multiple iteration types using
# multiple dispatch thanks to all the global
# constants, and by defining them as structs
# rather than enums we can pass arbitrary
# parameters to the iterator
abstract type ECSIterator <: System end

# refers to tree level, i.e. breadth-first,
# nothing special to see here
struct Level <: ECSIterator end 
const lvl = Level()
Base.length(l::Level) = length(ecs)

mutable struct ECSIteratorState
  root::Int
  q::Queue{Int}
  root_visited::Bool
  index::Int
  ECSIteratorState(; root=0, q=Queue{Int}(), root_visited=false, index=1) = new(root, q, root_visited, index)
end

function Base.iterate(l::Level, state::ECSIteratorState=ECSIteratorState())
  if isempty(state.q)
    if !state.root_visited # just started
      enqueue!(state.q, state.root)
      state.root_visited = true
    else # just finished
      return nothing
    end
  end

  ent = get_entity_by_id(dequeue!(state.q))

  for c in getproperty(ent, CHILDREN) 
    enqueue!(state.q, c)
  end

  return (ent, state)
end

listenFor(ecs, TICK)

function handleMessage(e::ECS, m::TICK)
  @debug "ECS tick"
  function _update!(ent::Entity)
    if getproperty(ent, ACTIVE) update!(ent, m.Δ) end
  end
  try
    map(_update!, lvl) # TODO investigate parallelization
  catch
    handleException()
  end
end

awake!(e::ECS) = e.awoken = all(map(awake!, lvl))
shutdown!(e::ECS) = e.awoken = all(map(shutdown!, lvl))

next_id = 0

function instantiate!(e::Entity; kw...)

  lock(ecs_lock)

  global next_id
  id = next_id
  next_id += 1

  # update ecs
  # allows invalid parents and children for now
  push!(ecs.df, Dict(
    ENT=>e,
    TYPE=>typeof(e),
    ID=>id,
    CHILDREN=>get(kw, :children, Set{Int}()),
    PARENT=>get(kw, :pid, 0),
    POSITION=>get(kw, :pos, XYZ()),
    ROTATION=>get(kw, :rot, XYZ()),
    ACTIVE=>get(kw, :active, true),
    HIDDEN=>get(kw, :hidden, false),
    PROPS=>merge(get(kw, :props, Dict{Symbol, Any}()), 
      Dict(k=>v for (k,v) in kw if k ∉ 
      [:children, :pid, :pos, :rot, :active, :hidden, :props]))
  ))

  if id != 0 # root has no parent but itself
    par = get_entity_by_id(get(kw, :pid, 0))
    push!(getproperty(par, CHILDREN), id)
  end

  unlock(ecs_lock)

  if ecs.awoken awake!(e) end

  return e
end

function destroy!(e::Entity)
  shutdown!(e)

  lock(ecs_lock)

  p = get_entity_by_id(getproperty(e, PARENT))

  # if not root
  if getproperty(p, ID) != getproperty(e, ID)
    # update parent
    delete!(getproperty(p, CHILDREN), getproperty(e, ID))
    # update dataframe
    deleteat!(ecs.df, getproperty(ecs.df, ENT) .== [e])
  end

  unlock(ecs_lock)
end

function destroy!(es...)
  map(destroy!, es) # TODO investigate parallelization
end

mutable struct Root <: Entity end # mutate at your own peril
# also, user can define update!(r::Root, Δ) if they want

# root pid is 0 (default) indicating "here and no further",
# instantiate in library because always needed, also it will
# always have id of 0, technically parent of itself
instantiate!(Root())
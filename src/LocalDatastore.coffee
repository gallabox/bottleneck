parser = require "./parser"
BottleneckError = require "./BottleneckError"

class LocalDatastore
  constructor: (@instance, @storeOptions, storeInstanceOptions) ->
    parser.load storeInstanceOptions, storeInstanceOptions, @
    @_nextRequest = Date.now()
    @_running = 0
    @_done = 0
    @_unblockTime = 0
    @ready = @yieldLoop()
    @clients = {}

  __publish__: (message) ->
    await @yieldLoop()
    @instance.Events.trigger "message", [message.toString()]

  __disconnect__: (flush) -> @Promise.resolve()

  yieldLoop: (t=0) -> new @Promise (resolve, reject) -> setTimeout resolve, t

  computePenalty: -> @storeOptions.penalty ? ((15 * @storeOptions.minTime) or 5000)

  __updateSettings__: (options) ->
    await @yieldLoop()
    parser.overwrite options, options, @storeOptions
    @instance._drainAll()
    true

  __running__: ->
    await @yieldLoop()
    @_running

  __done__: ->
    await @yieldLoop()
    @_done

  __groupCheck__: (time) ->
    await @yieldLoop()
    (@_nextRequest + @timeout) < time

  conditionsCheck: (weight) ->
    ((not @storeOptions.maxConcurrent? or @_running + weight <= @storeOptions.maxConcurrent) and
    (not @storeOptions.reservoir? or @storeOptions.reservoir - weight >= 0))

  __incrementReservoir__: (incr) ->
    await @yieldLoop()
    @storeOptions.reservoir += incr
    @instance._drainAll()

  __currentReservoir__: ->
    await @yieldLoop()
    @storeOptions.reservoir

  isBlocked: (now) -> @_unblockTime >= now

  check: (weight, now) -> @conditionsCheck(weight) and (@_nextRequest - now) <= 0

  __check__: (weight) ->
    await @yieldLoop()
    now = Date.now()
    @check weight, now

  __register__: (index, weight, expiration) ->
    await @yieldLoop()
    now = Date.now()
    if @conditionsCheck weight
      @_running += weight
      if @storeOptions.reservoir? then @storeOptions.reservoir -= weight
      wait = Math.max @_nextRequest - now, 0
      @_nextRequest = now + wait + @storeOptions.minTime
      { success: true, wait, reservoir: @storeOptions.reservoir }
    else { success: false }

  strategyIsBlock: -> @storeOptions.strategy == 3

  __submit__: (queueLength, weight) ->
    await @yieldLoop()
    if @storeOptions.maxConcurrent? and weight > @storeOptions.maxConcurrent
      throw new BottleneckError("Impossible to add a job having a weight of #{weight} to a limiter having a maxConcurrent setting of #{@storeOptions.maxConcurrent}")
    now = Date.now()
    reachedHWM = @storeOptions.highWater? and queueLength == @storeOptions.highWater and not @check(weight, now)
    blocked = @strategyIsBlock() and (reachedHWM or @isBlocked now)
    if blocked
      @_unblockTime = now + @computePenalty()
      @_nextRequest = @_unblockTime + @storeOptions.minTime
    { reachedHWM, blocked, strategy: @storeOptions.strategy }

  __free__: (index, weight) ->
    await @yieldLoop()
    @_running -= weight
    @_done += weight
    @instance._drainAll()
    { running: @_running }

module.exports = LocalDatastore
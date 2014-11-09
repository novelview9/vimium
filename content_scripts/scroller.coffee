window.Scroller = root = {}

#
# activatedElement is different from document.activeElement -- the latter seems to be reserved mostly for
# input elements. This mechanism allows us to decide whether to scroll a div or to scroll the whole document.
#
activatedElement = null
settings = null

root.init = (frontendSettings) ->
  settings = frontendSettings
  handlerStack.push DOMActivate: -> activatedElement = event.target

scrollProperties =
  x: {
    axisName: 'scrollLeft'
    max: 'scrollWidth'
    viewSize: 'clientHeight'
  }
  y: {
    axisName: 'scrollTop'
    max: 'scrollHeight'
    viewSize: 'clientWidth'
  }

getDimension = (el, direction, amount) ->
  if Utils.isString amount
    name = amount
    # the clientSizes of the body are the dimensions of the entire page, but the viewport should only be the
    # part visible through the window
    if name is 'viewSize' and el is document.body
      if direction is 'x' then window.innerWidth else window.innerHeight
    else
      el[scrollProperties[direction][name]]
  else
    amount

# Test whether element should be scrolled.
isScrollAllowed = (element, direction) ->
  # Elements with `overflow: hidden` should not be scrolled.
  window.getComputedStyle(element).getPropertyValue("overflow-#{direction}") != "hidden"

# Test whether element actually scrolls in the direction required when asked to do so.
# Due to chrome bug 110149, scrollHeight and clientHeight cannot be used to reliably determine whether an
# element will scroll.  Instead, we scroll the element by 1 or -1 and see if it moved.
isScrollPossible = (element, direction, amount, factor) ->
  axisName = scrollProperties[direction].axisName
  # delta, here, is treated as a relative amount, which is correct for relative scrolls. For absolute scrolls
  # (only gg, G, and friends), amount can be either 'max' or zero. In the former case, we're definitely
  # scrolling forwards, so any positive value will do for delta.  In the latter case, we're definitely
  # scrolling backwards, so a delta of -1 will do.
  delta = factor * getDimension(element, direction, amount) || -1
  delta = delta / Math.abs delta # 1 or -1
  before = element[axisName]
  element[axisName] += delta
  after = element[axisName]
  element[axisName] = before
  before != after

# Find the element we should and can scroll.
findScrollableElement = (element, direction, amount, factor = 1) ->
  axisName = scrollProperties[direction].axisName
  while element != document.body and
    not (isScrollPossible(element, direction, amount, factor) and isScrollAllowed(element, direction))
      element = element.parentElement || document.body
  element

performScroll = (element, axisName, amount, checkVisibility = true) ->
  before = element[axisName]
  element[axisName] += amount

  if checkVisibility
    # if the activated element has been scrolled completely offscreen, subsequent changes in its scroll
    # position will not provide any more visual feedback to the user. therefore we deactivate it so that
    # subsequent scrolls only move the parent element.
    rect = activatedElement.getBoundingClientRect()
    if (rect.bottom < 0 || rect.top > window.innerHeight || rect.right < 0 || rect.left > window.innerWidth)
      activatedElement = element

  # Return the amount by which the scroll position has changed.
  element[axisName] - before

# Scroll by a relative amount (a number) in some direction, possibly smoothly.
doScrollBy = do ->
  interval = 10 # Update interval (in ms).
  duration = 120 # This must be a multiple of interval (also in ms).
  fudgeFactor = 25
  timer = null

  clearTimer = ->
    if timer
      clearInterval timer
      timer = null

  # Allow a bit longer for longer scrolls.
  calculateExtraDuration = (amount) ->
    extra = fudgeFactor * Math.log Math.abs amount
    # Ensure we have a multiple of interval.
    return interval * Math.round (extra / interval)

  (element, direction, amount, wantSmooth) ->
    axisName = scrollProperties[direction].axisName
    clearTimer()

    unless wantSmooth and settings.get "smoothScroll"
      return performScroll element, axisName, amount

    requiredTicks = (duration + calculateExtraDuration amount) / interval
    # Round away from 0, so that we don't leave any scroll amount unscrolled.
    delta = (if 0 <= amount then Math.ceil else Math.floor)(amount / requiredTicks)

    if delta
      ticks = 0
      ticker = ->
        if performScroll(element, axisName, delta, false) != delta or ++ticks == requiredTicks
          # One final call of performScroll to check the visibility of the activated element.
          performScroll(element, axisName, 0, true)
          clearTimer()

      timer = setInterval ticker, interval
      ticker()

# scroll the active element in :direction by :amount * :factor.
# :factor is needed because :amount can take on string values, which scrollBy converts to element dimensions.
root.scrollBy = (direction, amount, factor = 1) ->
  # if this is called before domReady, just use the window scroll function
  if (!document.body and amount instanceof Number)
    if (direction == "x")
      window.scrollBy(amount, 0)
    else
      window.scrollBy(0, amount)
    return

  if (!activatedElement || !isRendered(activatedElement))
    activatedElement = document.body

  element = findScrollableElement activatedElement, direction, amount, factor
  elementAmount = factor * getDimension element, direction, amount
  doScrollBy element, direction, elementAmount, true

root.scrollTo = (direction, pos, wantSmooth = false) ->
  return unless document.body

  if (!activatedElement || !isRendered(activatedElement))
    activatedElement = document.body

  element = findScrollableElement activatedElement, direction, pos
  amount = getDimension(element,direction,pos) - element[scrollProperties[direction].axisName]
  doScrollBy element, direction, amount, wantSmooth

# TODO refactor and put this together with the code in getVisibleClientRect
isRendered = (element) ->
  computedStyle = window.getComputedStyle(element, null)
  return !(computedStyle.getPropertyValue("visibility") != "visible" ||
      computedStyle.getPropertyValue("display") == "none")

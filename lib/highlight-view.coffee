{CompositeDisposable, Emitter} = require 'event-kit'

class CoverageHighLightView
  constructor: (@editor) ->
    @emitter = new Emitter
    @subscriptions = new CompositeDisposable
    @markers = []


    @subscriptions.add @editor.onDidDestroy =>
      @remove()

  update: (file) ->
    @clearHighlights()
    for line in file.lines
      line = line - 1
      range = [[line, 0], [line, 0]]
      marker = @editor.markBufferRange(range, {invalidate: 'surround', class: 'coverage-line'})
      @editor.decorateMarker(marker, {type: 'line', class: 'coverage-line'})
      @markers.push marker

  clearHighlights: ->
    for marker in @markers
      marker.destroy()
    @markers = []

  remove: ->
    @clearHighlights()

    @subscriptions.dispose()
    @emitter.emit 'did-destroy'

  onDidDestroy: (callback) ->
    @emitter.on 'did-destroy', callback


module.exports = CoverageHighLightView

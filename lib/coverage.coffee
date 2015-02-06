_ = require 'lodash'
{CompositeDisposable} = require 'event-kit'

fs = require 'fs-plus'
path = require 'path'
et = require("elementtree")

process = require 'child_process'
exec = require('child_process').exec;

PanelView = require './panel-view'
StatusView = require './status-view'

CoverageHighLightView = require './highlight-view'


module.exports =
  config:
    coverageFilePath:
      type: "string"
      default: "tests/coverage.xml"
    coverageCommand:
      type: "string"
      default: "nosetests -v --cover-package={{module}} --with-coverage -e ^rtest.+$ --cover-erase --cover-xml --all-modules -w tests/"
    virtualEnv:
      type: "string"
      default: "../env"
    refreshOnFileChange:
      type: "boolean"
      default: true

  refreshOnFileChangeSubscription: null
  panelView: null
  statusView: null
  coverageFile: null
  pathWatcher: null

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @coverageHighLightViews = []

    @coverageFile = atom.project.resolve(atom.config.get("python-coverage.coverageFilePath")) if atom.project.path
    @panelView = new PanelView
    @panelView.initialize()

    # add the status bar and refresh the coverage after all packages are loaded
    if atom.workspaceView.statusBar
      @initializeStatusBarView()
    else
      atom.packages.once "activated", =>
        @initializeStatusBarView() if atom.workspaceView.statusBar

    # commands
    atom.workspaceView.command "python-coverage:toggle", => @panelView.toggle()
    atom.workspaceView.command "python-coverage:refresh", => @runAndUpdate()

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      return unless editor.getGrammar().name == 'Python'

      @handleEvents(editor)
      return if editor.coverageHighLight?

      coverageHighLightView = new CoverageHighLightView(editor)

      @coverageHighLightViews.push coverageHighLightView
      @subscriptions.add coverageHighLightView.onDidDestroy =>
        @coverageHighLightViews = _.without @coverageHighLightViews, coverageHighLightView

    # update coverage
    @update()

  initializeStatusBarView: ->
    @statusView = new StatusView
    @statusView.initialize(@panelView)
    atom.workspaceView.statusBar.appendLeft(@statusView)

    @panelView.header.addEventListener "click", => @runAndUpdate()

    @update()

  parseFloat: (element, attrib) ->
    return parseFloat(element.attrib[attrib])*100

  handleEvents: (editor) ->
    console.log("handleEvents")
    @update()
    editor.getBuffer().onWillSave =>
      console.log('saving: ')
      console.log(editor)
      if atom.config.get("python-coverage.refreshOnFileChange")
        @runAndUpdate()
      path = editor.getUri()
      console.log(path)

  runAndUpdate: ->
    coverageCommand =>
      @update()

  update: ->
    console.log('Updating: '+@coverageFile)
    if @coverageFile and fs.existsSync(@coverageFile)
      fs.readFile @coverageFile, "utf8", (error, data) =>
        return if error

        etree = et.parse(data)

        {packages, all_files} = @parseCoverageData(etree)

        total_percent = @parseFloat(etree.getroot(), 'line-rate')

        @updatePanelView packages
        @updateStatusBar total_percent
        @updateEditors all_files
    else
      @statusView?.notfound()

  updatePanelView: (packages) ->
    @panelView.update packages

  updateStatusBar: (total_percent) ->
    @statusView?.update Number(total_percent.toFixed(2))

  updateEditors: (all_files) ->
    for view  in @coverageHighLightViews
      if all_files[view.editor.getUri()]
        console.log('Updating: '+view.editor.getUri())
        view.update(all_files[view.editor.getUri()])

  parseCoverageData: (etree) ->
    all_files = {}
    packages = []
    for pack in etree.getroot().findall('./packages/package')
      p = {name: pack.attrib.name, 'covered_percent': @parseFloat(pack, 'line-rate'), files: []}
      for clazz in pack.findall('classes/class')
        lines = []
        covered_lines = 0
        for line in clazz.findall('lines/line')
          #console.log(line.attrib.number)
          if line.attrib.hits == "0"
            lines.push(line.attrib.number)
          else
            covered_lines++
        file = {'filename': clazz.attrib.filename, lines: lines, 'covered_percent': @parseFloat(clazz, 'line-rate'), 'lines_of_code': clazz.findall('lines/line').length, 'covered_lines': covered_lines}
        p.files.push(file)
        all_files[atom.project.resolve(clazz.attrib.filename)] = file
      packages.push(p)
    return {packages, all_files}

  serialize: ->

  deactivate: ->
    @panelView?.destroy()
    @panelView = null

    @statusView?.destroy()
    @statusView = null

    @coverageFile = null

    @subscriptions.dispose()



detectModule = (callback) ->
  ve = atom.config.get "python-coverage.virtualEnv"
  dir = atom.project.path
  cmd = 'python -c "from setuptools import find_packages; print find_packages(\\"src\\")[0]"'
  cmd = "exec bash -c 'cd #{dir} && source #{ve}/bin/activate && #{cmd}'"

  child = exec(cmd);
  buffer = ''
  child.stdout.on 'data', (data) ->
    buffer += data;
  child.on 'close', (code) ->
    callback(buffer.trim())


coverageCommand = (callback) ->
  ve = atom.config.get "python-coverage.virtualEnv"
  cmd = atom.config.get "python-coverage.coverageCommand"
  dir = atom.project.path

  detectModule (module) ->
    cmd = cmd.interp
      module: module
    cmd = "exec bash -c 'cd #{dir} && source #{ve}/bin/activate && #{cmd}'"

    child = exec(cmd);
    child.stdout.on 'data', (data) ->
        console.log(data);
    child.stderr.on 'data', (data) ->
        console.log(data);
    child.on 'close', (code) ->
      if code == 0
        callback()


String::interp = (values)->
    @replace /{{(\w*)}}/g,
        (ph, key)->
            values[key] or ''

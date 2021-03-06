module.exports = ->
  # Project configuration
  @initConfig
    pkg: @file.readJSON 'package.json'

    # CoffeeScript compilation of tests
    coffee:
      main:
        src: 'index.coffee'
        dest: 'build/flatten-html.js'

    # Automated recompilation and testing when developing
    watch:
      files: ['spec/*.coffee', 'index.coffee']
      tasks: ['test']

    # BDD tests on Node.js
    mochaTest:
      nodejs:
        src: ['spec/*.coffee']
        options:
          reporter: 'spec'
          require: 'coffee-script/register'
          grep: process.env.TESTS

    # BDD tests on browser
    mocha_phantomjs:
      options:
        output: 'spec/result.xml'
        failWithOutput: true
        reporter: 'spec'
      all: ['spec/runner.html']

    # Coding standards
    coffeelint:
      components: ['Gruntfile.coffee', 'spec/*.coffee', 'index.coffee']
      options:
        'max_line_length':
          'level': 'ignore'

    # Build tests
    browserify:
      spec:
        files:
          'build/spec.js': ['spec/*.coffee']
        options:
          transform: ['coffeeify', 'brfs']

  # Grunt plugins used for building
  @loadNpmTasks 'grunt-contrib-coffee'

  # Grunt plugins used for testing
  @loadNpmTasks 'grunt-contrib-watch'
  @loadNpmTasks 'grunt-mocha-test'
  @loadNpmTasks 'grunt-mocha-phantomjs'
  @loadNpmTasks 'grunt-coffeelint'
  @loadNpmTasks 'grunt-browserify'

  # Our local tasks
  @registerTask 'build', 'Build NoFlo for the chosen target platform', (target = 'all') =>
    if target is 'all' or target is 'main'
      @task.run 'coffee:main'
    if target is 'all' or target is 'spec'
      @task.run 'browserify'

  @registerTask 'test', 'Build NoFlo and run automated tests', (target = 'all') =>
    @task.run 'coffeelint'
    @task.run 'coffee'
    if target is 'all' or target is 'nodejs'
      @task.run 'mochaTest'
    if target is 'all' or target is 'browser'
      @task.run 'mocha_phantomjs'

  @registerTask 'default', ['test']

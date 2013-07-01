define [
  'jquery'
  'underscore'
  'backbone'
  'cs!models/content/inherits/base'
], ($, _, Backbone, BaseModel) ->

  # Backbone Collection used to store a container's contents
  class Container extends Backbone.Collection
    findMatch: (model) ->
      return _.find @titles, (obj) ->
        return model.id is obj.id or model.cid is obj.id

    getTitle: (model) ->
      if model.unique
        return model.get('title')

      return @findMatch(model)?.title or model.get('title')

    setTitle: (model, title) ->
      if model.unique
        model.set('title', title)
      else
        match = @findMatch(model)

        if match
          match.title = title
        else
          @titles.push
            id: model.id or model.cid
            mediaType: model.mediaType
            title: title

        model.trigger('change')

      return @

  # Helper function to parse html-encoded data
  parseHTML = (html) ->
    if typeof html isnt 'string' then return []

    results = []

    $(html).find('> ol').find('> li').each (index, el) ->
      $el = $(el)
      $node = $el.children().eq(0)

      if $node.is('a')
        id = $node.attr('href')
        title = $node.text()

      # Only remember the title if it's overridden
      if not title or $node.hasClass('autogenerated-text')
        results.push({id: id})
      else
        results.push({id: id, title: title})

    return results

  class ContainerModel extends BaseModel
    mediaType: 'application/vnd.org.cnx.folder'
    accept: []
    unique: true
    branch: true
    expanded: false
    promise: () -> return @_deferred.promise()

    toJSON: () ->
      json = super()

      contents = @getChildren() or {}

      json.contents = []
      _.each contents.models, (item) ->
        obj = {}
        title = contents.getTitle?(item) or contents.get 'title'
        if item.id then obj.id = item.id
        if title then obj.title = title

        json.contents.push(obj)

      return json

    accepts: (mediaType) ->
      if (typeof mediaType is 'string')
        return _.indexOf(@accept, mediaType) is not -1

      return @accept

    initialize: (attrs) ->
      @_deferred = $.Deferred()

      if not @isNew()
        @loading = true
        @fetch
          silent: true
          loading: true
          success: (model, response, options) =>
            @loading = false
      else
        @_deferred.resolve()

    getChildren: () -> @get('contents')

    add: (models, options) ->
      if (!_.isArray(models)) then (models = if models then [models] else [])

      _.each models, (model, index, arr) =>
        contents = @getChildren()

        # Add new media to the beginning of the array
        if contents.length and not options?.loading
          @getChildren().unshift(model)
        else
          @getChildren().add(model)

      if not options?.silent then @trigger('change')

      return @

    set: (key, val, options) ->
      if (key == null) then return this;

      if typeof key is 'object'
        attrs = key
        options = val
      else
        (attrs = {})[key] = val

      options = options || {}
      contents = attrs.contents or attrs.body

      if contents
        if not _.isArray(contents)
          contents = parseHTML(contents)

        attrs.contents = @getChildren() or new Container()
        attrs.contents.titles = contents

        require ['cs!collections/content'], (content) =>
          content.loading().done () =>
            _.each contents, (item) =>
              @add(content.get({id: item.id}), options)
            @_deferred.resolve()

      return super(attrs, options)

    # Change the content view when editing this
    contentView: (callback) ->
      require ['cs!views/workspace/content/search-results'], (View) =>
        view = new View({collection: @getChildren()})
        callback(view)

    # Change the sidebar view when editing this
    sidebarView: (callback) ->
      require ['cs!views/workspace/sidebar/toc'], (View) =>
        view = new View
          collection: @getChildren()
          model: @
        callback(view)

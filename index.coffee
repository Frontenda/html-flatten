htmlparser = require 'htmlparser'
he = require 'he'
uri = require 'urijs'
Promise = require 'bluebird'

module.exports = class Flatten
  structuralTags: [
    '?xml'
    '!DOCTYPE'
    'html'
    'head'
    'link'
    'style'
    'title'
    'body'
    'div'
    'font'
    'section'
    'span'
    'header'
    'footer'
    'nav'
    'br'
    'meta'
    's'
    'small'
    'script'
  ]
  blockLevel: [
    'p'
    'h1'
    'h2'
    'h3'
    'h4'
    'h5'
    'h6'
    'h7'
    'div'
    'blockquote'
    'pre'
  ]
  ignoredAttribs: [
    'data-query-source'
    'data-expanded-url'
    'data-grid-id'
  ]
  allowedAttribs: [
    'src'
    'href'
    'title'
    'alt'
    'webkitallowfullscreen'
    'mozallowfullscreen'
    'allowfullscreen'
    'width'
    'height'
    'scrolling'
    'frameborder'
    'autoplay'
    'loop'
    'controls'
    'type'
  ]

  constructor: (options={}) ->
    if options.structuralTags?
      @structuralTags = options.structuralTags
    if options.ignoredAttribs?
      @ignoredAttribs = options.ignoredAttribs
    if options.allowedAttribs?
      @allowedAttribs = options.allowedAttribs

  processPage: (page, callback) ->
    if page.html and not page.items
      @flattenItem page, (err) ->
        return callback err if err
        callback null, page
      return

    unless page.items?.length
      callback null, page
      return

    flattenItem = Promise.promisify @flattenItem.bind @
    Promise.map page.items, (item) ->
      flattenItem item
    .nodeify (err) ->
      return callback err if err
      callback null, page

  flattenItem: (item, callback) ->
    if item.content and not item.html
      # Pre-flattened item, just make sure HTML is sane
      return @cleanUpItem item, callback

    item.html = '' unless item.html
    if item.html and not item.html.match /^[\s]*</
      item.html = "<p>#{item.html}</p>"

    handler = new htmlparser.DefaultHandler (err, dom) =>
      item.content = []
      for tag in dom
        normalized = @normalizeTag tag, item.id
        continue unless normalized
        for block in normalized
          item.content.push block
      delete item.html
      callback null, item
    ,
      ignoreWhitespace: true
    parser = new htmlparser.Parser handler
    parser.parseComplete item.html

  cleanUpItem: (item, callback) ->
    cleanUp = Promise.promisify @cleanUpBlock.bind @
    Promise.map item.content, (block) ->
      cleanUp block, item
    .nodeify (err) ->
      return callback err if err
      callback null, item

  cleanUpBlock: (block, item, callback) ->
    return callback null unless block
    if block.type is 'placeholder'
      block.html = ''
      do callback
      return
    handler = new htmlparser.DefaultHandler (err, dom) =>
      blocks = []
      for tag in dom
        normalized = @normalizeTag tag, item.id
        continue unless normalized
        for b in normalized
          blocks.push b

      blockIdx = item.content.indexOf block
      #return callback() if blockIdx is -1
      unless blocks.length
        # Empty block, remove
        item.content.splice blockIdx, 1
        return callback()
      if blocks.length is 1
        # Block returned only one block, update values
        item.content[blockIdx][k] = v for k, v of blocks[0]
        return callback()

      if block.type is blocks[0].type
        # First result is still the original, update that and add the others
        [first, blocks...] = blocks
        item.content[blockIdx][k] = v for k, v of first
        for b, i in blocks
          item.content.splice blockIdx + 1 + i, 0, b
        return callback()

      [first, blocks...] = blocks
      item.content[blockIdx] = first
      for b, i in blocks
        item.content.splice blockIdx + 1 + i, 0, b
      do callback
    ,
      ignoreWhitespace: true
    parser = new htmlparser.Parser handler
    parser.parseComplete block.html

  normalizeUrl: (url, base) ->
    return url unless base
    return '' unless url
    parsed = uri url
    return url if parsed.protocol() in ['javascript', 'mailto', 'data', 'blob', 'filesystem', 'file', 'chrome-extension', 'filesystem:chrome-extension']
    try
      abs = parsed.absoluteTo(base).toString()
    catch e
      console.log url, e
      return url
    abs

  normalizeTag: (tag, id) ->
    results = []

    if tag.type is 'text'
      results.push
        type: 'text'
        html: @tagToHtml tag, id
      return results

    if tag.name in @structuralTags
      return results unless tag.children
      for child in tag.children
        continue if child.type is 'text'
        normalized = @normalizeTag child, id
        continue unless normalized
        results = results.concat normalized
      return results

    switch tag.name
      when 'video'
        tag.attribs.src = @normalizeUrl tag.attribs.src, id if tag.attribs.src
        video =
          type: 'video'
          html: @tagToHtml tag, id
        video.video = tag.attribs.src if tag.attribs.src
        results.push video
      when 'iframe'
        return results unless tag.attribs
        tag.attribs.src = @normalizeUrl tag.attribs.src, id
        if tag.attribs.src.indexOf('vimeo.com') isnt -1
          results.push
            type: 'video'
            video: tag.attribs.src
            html: @tagToHtml tag, id
        else if tag.attribs.src.indexOf('youtube.com') isnt -1
          results.push
            type: 'video'
            video: tag.attribs.src
            html: @tagToHtml tag, id
        else if tag.attribs.src.indexOf('vine.co') isnt -1
          results.push
            type: 'video'
            video: tag.attribs.src
            html: @tagToHtml tag, id
        else if tag.attribs.src.indexOf('fast.wistia.net') isnt -1
          results.push
            type: 'video'
            video: tag.attribs.src
            html: @tagToHtml tag, id
        else if tag.attribs.src.indexOf('i.imgur.com') isnt -1 and tag.attribs.src.indexOf('gifv') isnt -1
          results.push
            type: 'video'
            video: tag.attribs.src
            html: @tagToHtml tag, id
        else if tag.attribs.src.indexOf('cdninstagram.com') isnt -1
          results.push
            type: 'video'
            video: tag.attribs.src
            html: @tagToHtml tag, id
        else if tag.attribs.src.indexOf('livestream.com') isnt -1
          results.push
            type: 'video'
            video: tag.attribs.src
            html: @tagToHtml tag, id
        else if tag.attribs.src.indexOf('maps.google.') isnt -1
          results.push
            type: 'location'
            html: @tagToHtml tag, id
        else if tag.attribs.src.indexOf('soundcloud.com') isnt -1
          results.push
            type: 'audio'
            video: tag.attribs.src
            html: @tagToHtml tag, id
        else if tag.attribs.src.indexOf('bandcamp.com') isnt -1
          results.push
            type: 'audio'
            video: tag.attribs.src
            html: @tagToHtml tag, id
        else
          results.push
            type: 'interactive'
            html: @tagToHtml tag, id
      when 'img'
        return results unless tag.attribs
        tag.attribs.src = @normalizeUrl tag.attribs.src, id
        if tag.attribs.src is 'http://en.wikipedia.org/wiki/Special:CentralAutoLogin/start?type=1x1'
          return results
        img =
          type: 'image'
          src: tag.attribs.src
          html: @tagToHtml tag, id
        img.title = he.decode(tag.attribs.title) if tag.attribs.title
        img.caption = he.decode(tag.attribs.alt) if tag.attribs.alt
        results.push img
      when 'figure'
        return results unless tag.children
        type = 'image'
        src = undefined
        caption = null
        for child in tag.children
          if child.name in @structuralTags
            normalized = @normalizeTag child, id
            for n in normalized
              if n.type is 'image'
                src = n.src
          if child.name is 'iframe'
            return @normalizeTag child, id
          if child.name is 'code'
            type = 'code'
          if child.name is 'img'
            if child.attribs
              child.attribs.src = @normalizeUrl child.attribs.src, id
              src = child.attribs.src
            type = 'image'
          if child.name is 'figcaption'
            caption = @tagToHtml child, id, false
        img =
          type: type
          src: src
          html: @tagToHtml tag, id, true
        img.caption = he.decode(caption) if caption
        results.push img
      when 'article'
        return results unless tag.children
        caption = null
        title = null
        src = null
        for child in tag.children
          if child.name is 'h1' and not title
            title = ''
            continue unless child.children
            title += @tagToHtml c for c in child.children
          if child.name is 'p' and not caption
            caption = ''
            continue unless child.children
            caption += @tagToHtml c for c in child.children
          if child.name is 'img' and child.attribs.src and not src
            src = @normalizeUrl child.attribs.src, id
         article =
           type: 'article'
           html: @tagToHtml tag, id
         article.title = he.decode(title) if title
         article.caption = he.decode(caption) if caption
         article.src = src if src
         results.push article
      when 'p', 'em', 'small'
        return unless tag.children
        hasContent = false
        normalized = []
        remove = []
        for child in tag.children
          if child.name is 'video'
            normalized = normalized.concat @normalizeTag child, id
            remove.push child
          else if child.name is 'img'
            normalized = normalized.concat @normalizeTag child, id
            remove.push child
          else if child.name is 'button'
            normalized = normalized.concat @normalizeTag child, id
            remove.push child
          else if child.name is 'a'
            normalizedChild = @normalizeTag child, id
            for n in normalizedChild
              continue unless n.type in ['image', 'video']
              normalized.push n
              remove.push child
          else
            hasContent = true
        # If we only have images or videos inside, then return them
        # as individual items
        for r in remove
          tag.children.splice tag.children.indexOf(r), 1

        # If we have other stuff too, then return them as-is
        html = @tagToHtml tag, id
        unless html is '<p></p>'
          results.push
            type: 'text'
            html: html

        if normalized.length
          results.push n for n in normalized
      when 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'
        normalized =
          type: tag.name
          html: @tagToHtml tag, id
        normalized.text = @tagToText tag
        results.push normalized
      when 'pre'
        results.push
          type: 'code'
          html: @tagToHtml tag, id
      when 'ul', 'ol', 'dl'
        results.push
          type: 'list'
          html: @tagToHtml tag, id
      when 'blockquote'
        results.push
          type: 'quote'
          html: @tagToHtml tag, id
          text: @tagToText tag
      when 'table'
        results.push
          type: 'table'
          html: @tagToHtml tag, id
      when 'time'
        results.push
          type: 'time'
          html: @tagToHtml tag, id
      when 'a'
        return results unless tag.children
        if tag.attribs?.href
          tag.attribs.href = @normalizeUrl tag.attribs.href, id
        normalizedChildren = []
        for c in tag.children
          normalizedChildren = normalizedChildren.concat @normalizeTag c, id
        return results unless normalizedChildren.length
        if tag.attribs?.href
          normalizedChildren[0].html = @tagToHtml tag, id
        return normalizedChildren
      when 'button'
        return results unless tag.attribs?['data-role']
        normalized = {}
        for key, val of tag.attribs
          continue unless key.indexOf('data-') is 0
          attrib = key.substr 5
          attrib = 'type' if attrib is 'role'
          normalized[attrib] = val
        normalized.html = @tagToHtml tag, id
        results.push normalized
        return results
      # Tags that we ignore entirely
      when 'form', 'input', 'textarea', 'aside', 'meta', 'script', 'hr', 'br'
        return results
      else
        results.push
          type: 'unknown'
          html: @tagToHtml tag, id
    results

  isAttributeAllowed: (attribute) ->
    if attribute.substr(0, 5) is 'data-'
      return false if attribute in @ignoredAttribs
      return true
    return false unless attribute in @allowedAttribs
    true

  tagToHtml: (tag, id, keepCaption = false, allowBlock = true) ->
    if tag.type is 'text'
      return '' unless tag.data
      return '' if tag.data.trim() is ''
      return '' if tag.data is '&nbsp;'
      return tag.data
    allowSubBlock = tag.name in ['video', 'article', 'figure', 'blockquote']

    if tag.name in @blockLevel and not tag.children
      return ''

    if tag.name in @structuralTags or (tag.name in ['figcaption'] and not keepCaption)
      return '' unless tag.children
      content = ''
      for child in tag.children
        content += @tagToHtml child, id, keepCaption, allowSubBlock
      return content
    if tag.name in @blockLevel and not allowBlock
      content = ''
      for child in tag.children
        content += @tagToHtml child, id, keepCaption, allowSubBlock
      return content

    attributes = ''
    if tag.attribs
      for attrib, val of tag.attribs
        continue unless @isAttributeAllowed attrib
        if tag.name is 'a' and attrib is 'href'
          val = @normalizeUrl val, id
        if tag.name is 'img' and attrib is 'src'
          val = @normalizeUrl val, id
        attributes += " #{attrib}=\"#{val}\""
    html = "<#{tag.name}#{attributes}>"
    if tag.children
      content = ''
      for child, index in tag.children
        # Allow internal line breaks
        if child.name is 'br' and content isnt ''
          nextSibling = tag.children[index+1]
          if nextSibling and nextSibling.name isnt 'br'
            content += '<br>'
            continue
        content += @tagToHtml child, id, keepCaption, allowSubBlock
      html += content
    if tag.name isnt 'img' and tag.name isnt 'source'
      html += "</#{tag.name}>"
    return html

  tagToText: (tag) ->
    text = ''
    if tag.type is 'text'
      return he.decode tag.data
    if tag.name is 'br'
      return ' '
    if tag.children
      for child in tag.children
        text += @tagToText child
    text

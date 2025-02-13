# MIT License
# 
# Copyright (c) 2022 Can Joshua Lehmann
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Default widgets

import std/[unicode, os, sets, tables, options, asyncfutures, strutils, sequtils, sugar, strformat, hashes, times]
when defined(nimPreviewSlimSystem):
  import std/assertions
import widgetdef, cairo, widgetutils, common
import bindings/gtk

customPragmas()
when defined(owlkettleDocs) and isMainModule:
  echo "# Widgets"

type 
  Margin* = object
    top*, bottom*, left*, right*: int

  StyleClass* = distinct string

proc `$`*(x: StyleClass): string = x.string
proc hash*(x: StyleClass): Hash {.borrow.}
proc `==`*(x, y: StyleClass): bool {.borrow.}

renderable BaseWidget:
  ## The base widget of all widgets. Supports redrawing the entire Application
  ## by calling `<WidgetName>State.app.redraw()`
  privateMargin {.private.}: Margin = Margin() ## Allows setting top, bottom, left and right margin of a widget. Margin has those names as fields to set integer values to.
  privateStyle {.private.}: HashSet[StyleClass] = initHashSet[StyleClass]()
  sensitive: bool = true ## If the widget is interactive
  sizeRequest: tuple[x, y: int] = (-1, -1) ## Requested widget size. A value of -1 means that the natural size of the widget will be used.
  tooltip: string = "" ## The widget's tooltip is shown on hover

  hooks privateMargin:
    (build, update):
      if widget.hasPrivateMargin:
        state.privateMargin = widget.valPrivateMargin
        gtk_widget_set_margin_top(state.internalWidget, cint(state.privateMargin.top))
        gtk_widget_set_margin_bottom(state.internalWidget, cint(state.privateMargin.bottom))
        gtk_widget_set_margin_start(state.internalWidget, cint(state.privateMargin.left))
        gtk_widget_set_margin_end(state.internalWidget, cint(state.privateMargin.right))

  hooks privateStyle:
    (build, update):
      updateStyle(state, widget)

  hooks sensitive:
    property:
      gtk_widget_set_sensitive(state.internalWidget, cbool(ord(state.sensitive)))
  
  hooks sizeRequest:
    property:
      gtk_widget_set_size_request(
        state.internalWidget,
        cint(state.sizeRequest.x),
        cint(state.sizeRequest.y)
      )

  hooks tooltip:
    property:
      if state.tooltip.len > 0:
        gtk_widget_set_tooltip_text(state.internalWidget, state.tooltip.cstring)
      else:
        gtk_widget_set_has_tooltip(state.internalWidget, cbool(0))
  
  setter margin: int
  setter margin: Margin
  setter style: StyleClass # Applies CSS classes to the widget. There are some pre-defined classes available. You can also use custom CSS classes using `StyleClass("my-class")`.
  setter style: varargs[StyleClass] # Applies CSS classes to the widget.
  setter style: HashSet[StyleClass] # Applies CSS classes to the widget.

proc `hasMargin=`*(widget: BaseWidget, has: bool) =
  widget.hasPrivateMargin = has

proc `valMargin=`*(widget: BaseWidget, width: int) =
  widget.valPrivateMargin = Margin(top: width, bottom: width, left: width, right: width)

proc `valMargin=`*(widget: BaseWidget, margin: Margin) =
  widget.valPrivateMargin = margin

proc `hasStyle=`*(widget: BaseWidget, has: bool) =
  widget.hasPrivateStyle = has

proc `valStyle=`*(widget: BaseWidget, cssClasses: HashSet[StyleClass]) =
  widget.valPrivateStyle = cssClasses

proc `valStyle=`*(widget: BaseWidget, cssClasses: varargs[StyleClass]) =
  widget.valPrivateStyle = cssClasses.toHashSet()

proc `valStyle=`*(widget: BaseWidget, cssClass: StyleClass) =
  widget.valPrivateStyle = [cssClass].toHashSet()

renderable BaseWindow of BaseWidget:
  defaultSize: tuple[width, height: int] = (800, 600) ## Initial size of the window
  fullscreened: bool
  iconName: string
  
  proc close() ## Called when the window is closed
  
  hooks:
    connectEvents:
      state.connect(state.close, "destroy", eventCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.close)
  
  hooks defaultSize:
    property:
      gtk_window_set_default_size(state.internalWidget,
        state.defaultSize.width.cint,
        state.defaultSize.height.cint
      )
  
  hooks fullscreened:
    property:
      if state.fullscreened:
        gtk_window_fullscreen(state.internalWidget)
      else:
        gtk_window_unfullscreen(state.internalWidget)
  
  hooks iconName:
    property:
      gtk_window_set_icon_name(state.internalWidget, state.iconName.cstring)

renderable Window of BaseWindow:
  title: string
  titlebar: Widget ## Custom widget set as the titlebar of the window
  child: Widget
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_window_new(GTK_WINDOW_TOPLEVEL)
  
  hooks title:
    property:
      if state.titlebar.isNil:
        gtk_window_set_title(state.internalWidget, state.title.cstring)
  
  hooks titlebar:
    (build, update):
      state.updateChild(state.titlebar, widget.valTitlebar, gtk_window_set_titlebar)
  
  hooks child:
    (build, update):
      state.updateChild(state.child, widget.valChild, gtk_window_set_child)
  
  adder add:
    ## Adds a child to the window. Each window may only have one child.
    if widget.hasChild:
      raise newException(ValueError, "Unable to add multiple children to a Window. Use a Box widget to display multiple widgets in a Window.")
    widget.hasChild = true
    widget.valChild = child
  
  adder addTitlebar:
    ## Sets a custom titlebar for the window
    widget.hasTitlebar = true
    widget.valTitlebar = child
  
  example:
    Window:
      Label(text = "Hello, world")

type Orient* = enum OrientX, OrientY

proc toGtk(orient: Orient): GtkOrientation =
  result = [GTK_ORIENTATION_HORIZONTAL, GTK_ORIENTATION_VERTICAL][ord(orient)]

const
  BoxLinked* = "linked".StyleClass
  BoxCard* = "card".StyleClass
  BoxToolbar* = "toolbar".StyleClass
  BoxOsd* = "osd".StyleClass

type BoxChild[T] = object
  widget: T
  expand: bool
  hAlign: Align
  vAlign: Align

proc assignApp[T](child: BoxChild[T], app: Viewable) =
  child.widget.assignApp(app)

renderable Box of BaseWidget:
  ## A Box arranges its child widgets along one dimension.
  orient: Orient ## Orientation of the Box and its containing elements. May be one of OrientX (to orient horizontally) or OrientY (to orient vertically)
  spacing: int ## Spacing between the children of the Box
  children: seq[BoxChild[Widget]]

  hooks:
    beforeBuild:
      state.internalWidget = gtk_box_new(
        toGtk(widget.valOrient),
        widget.valSpacing.cint
      )
  
  hooks spacing:
    property:
      gtk_box_set_spacing(state.internalWidget, state.spacing.cint)

  hooks children:
    (build, update):
      widget.valChildren.assignApp(state.app)
      var it = 0
      while it < widget.valChildren.len and it < state.children.len:
        let
          child = widget.valChildren[it]
          newChild = child.widget.update(state.children[it].widget)
        if not newChild.isNil:
          gtk_box_remove(
            state.internalWidget,
            state.children[it].widget.unwrapInternalWidget()
          )
          var sibling: GtkWidget = nil.GtkWidget
          if it > 0:
            sibling = state.children[it - 1].widget.unwrapInternalWidget()
          let newWidget = newChild.unwrapInternalWidget()
          gtk_box_insert_child_after(state.internalWidget, newWidget, sibling)
          state.children[it].widget = newChild
        
        let childWidget = state.children[it].widget.unwrapInternalWidget()
        
        if not newChild.isNil or child.expand != state.children[it].expand:
          case state.orient:
            of OrientX: gtk_widget_set_hexpand(childWidget, child.expand.ord.cbool)
            of OrientY: gtk_widget_set_vexpand(childWidget, child.expand.ord.cbool)
          state.children[it].expand = child.expand
        
        if not newChild.isNil or child.hAlign != state.children[it].hAlign:
          state.children[it].hAlign = child.hAlign
          gtk_widget_set_halign(childWidget, toGtk(child.hAlign))
        
        if not newChild.isNil or child.vAlign != state.children[it].vAlign:
          state.children[it].vAlign = child.vAlign
          gtk_widget_set_valign(childWidget, toGtk(child.vAlign))
        
        it += 1
      
      while it < widget.valChildren.len:
        let
          child = widget.valChildren[it]
          childState = child.widget.build()
          childWidget = childState.unwrapInternalWidget()
        case state.orient:
          of OrientX: gtk_widget_set_hexpand(childWidget, child.expand.ord.cbool)
          of OrientY: gtk_widget_set_vexpand(childWidget, child.expand.ord.cbool)
        gtk_widget_set_halign(childWidget, toGtk(child.hAlign))
        gtk_widget_set_valign(childWidget, toGtk(child.vAlign))
        gtk_box_append(state.internalWidget, childWidget)
        state.children.add(BoxChild[WidgetState](
          widget: childState,
          expand: child.expand,
          hAlign: child.hAlign,
          vAlign: child.vAlign
        ))
        it += 1
      
      while it < state.children.len:
        gtk_box_remove(
          state.internalWidget,
          state.children[^1].widget.unwrapInternalWidget()
        )
        discard state.children.pop()

  adder add {.expand: true,
              hAlign: AlignFill,
              vAlign: AlignFill.}:
    ## Adds a child to the Box.
    ## When expand is true, the child grows to fill up the remaining space in the Box.
    ## The `hAlign` and `vAlign` properties allow you to set the horizontal and vertical 
    ## alignment of the child within its allocated area. They may be one of `AlignFill`, 
    ## `AlignStart`, `AlignEnd` or `AlignCenter`.
    widget.valChildren.add(BoxChild[Widget](
      widget: child,
      expand: expand,
      hAlign: hAlign, 
      vAlign: vAlign
    ))
  
  example:
    Box:
      orient = OrientX
      Label(text = "Label")
      Button(text = "Button") {.expand: false.}
  
  example:
    Box:
      orient = OrientY
      margin = 12
      spacing = 6
      
      for it in 0..<5:
        Label(text = "Label " & $it)
  
  example:
    HeaderBar {.addTitlebar.}:
      Box {.addLeft.}:
        style = [BoxLinked]
        
        for it in 0..<5:
          Button {.expand: false.}:
            text = "Button " & $it
            proc clicked() =
              echo it

type BaselinePosition* = enum
  BaselineTop, BaselineCenter, BaselineBottom

proc toGtk(x: BaselinePosition): GtkBaselinePosition = GtkBaselinePosition(ord(x))

renderable CenterBox of BaseWidget:
  startWidget: Widget
  centerWidget: Widget
  endWidget: Widget
  baselinePosition: BaselinePosition = BaselineCenter
  shrinkCenterLast: bool = false ## Requires GTK 4.12 or higher to work. Compile with `-d:gtkminor=12` to enable it
  orient: Orient = OrientX
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_center_box_new()

  hooks startWidget:
    (build, update):
      state.updateChild(state.startWidget, widget.valStartWidget, gtk_center_box_set_start_widget)
  
  hooks endWidget:
    (build, update):
      state.updateChild(state.endWidget, widget.valEndWidget, gtk_center_box_set_end_widget)
  
  hooks centerWidget:
    (build, update):
      state.updateChild(state.centerWidget, widget.valCenterWidget, gtk_center_box_set_center_widget)

  hooks baselinePosition:
    property:
      gtk_center_box_set_baseline_position(state.internalWidget, state.baselinePosition.toGtk())

  hooks shrinkCenterLast:
    property:
      when GtkMinor >= 12:
        gtk_center_box_set_shrink_center_last(state.internalWidget, state.shrinkCenterLast.cbool)

  hooks orient:
    property:
      gtk_orientable_set_orientation(state.internalWidget, state.orient.toGtk())

  adder addStart:
    if widget.hasStartWidget:
      raise newException(ValueError, "Unable to add multiple children to the start of CenterBox.")
    widget.hasStartWidget = true
    widget.valStartWidget = child

  adder addEnd:
    if widget.hasEndWidget:
      raise newException(ValueError, "Unable to add multiple children to the end of CenterBox.")
    widget.hasEndWidget = true
    widget.valEndWidget = child

  adder add:
    if widget.hasCenterWidget:
      raise newException(ValueError, "Unable to add multiple children to the center of CenterBox.")
    widget.hasCenterWidget = true
    widget.valCenterWidget = child

renderable Overlay of BaseWidget:
  child: Widget
  overlays: seq[AlignedChild[Widget]]
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_overlay_new()
  
  hooks child:
    (build, update):
      state.updateChild(state.child, widget.valChild, gtk_overlay_set_child)
  
  hooks overlays:
    (build, update):
      state.updateAlignedChildren(
        state.overlays,
        widget.valOverlays,
        gtk_overlay_add_overlay,
        gtk_overlay_remove_overlay
      )
  
  adder add:
    if widget.hasChild:
      raise newException(ValueError, "Unable to add multiple children to an Overlay. You can add overlays using the addOverlay adder.")
    widget.hasChild = true
    widget.valChild = child
  
  adder addOverlay {.hAlign: AlignFill,
                     vAlign: AlignFill.}:
    widget.hasOverlays = true
    widget.valOverlays.add(AlignedChild[Widget](
      widget: child,
      hAlign: hAlign,
      vAlign: vAlign
    ))

renderable EmojiChooser of BaseWidget:
  
  proc emojiPicked(emoji: string)
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_emoji_chooser_new()
    
    connectEvents:
      proc emojiPickedCallback(widget: GtkWidget, pickedEmoji: cstring, data: ptr EventObj[proc (emoji: string)]) {.cdecl.} =
        data[].callback($pickedEmoji)
        data[].redraw()
    
      state.connect(state.emojiPicked, "emoji-picked", emojiPickedCallback)
      
    disconnectEvents:
      state.internalWidget.disconnect(state.emojiPicked)
  

const
  LabelTitle1* = "title-1".StyleClass
  LabelTitle2* = "title-2".StyleClass
  LabelTitle3* = "title-3".StyleClass
  LabelTitle4* = "title-4".StyleClass
  LabelHeading* = "heading".StyleClass
  LabelBody* = "body".StyleClass
  LabelMonospace* = "monospace".StyleClass

type EllipsizeMode* = enum
  ## Determines whether to ellipsize text when text does not fit in a given space
  EllipsizeNone ## Do not ellipsize 
  EllipsizeStart, ## Start ellipsizing at the start of the text
  EllipsizeMiddle, ## Start ellipsizing in the middle of the text
  EllipsizeEnd ## Start ellipsizing at the end of the text

renderable Label of BaseWidget:
  ## The default widget to display text.
  ## Supports rendering [Pango Markup](https://docs.gtk.org/Pango/pango_markup.html#pango-markup) 
  ## if `useMarkup` is enabled.
  text: string ## The text of the Label to render
  xAlign: float = 0.5
  yAlign: float = 0.5
  ellipsize: EllipsizeMode ## Determines whether to ellipsise the text in case space is insufficient to render all of it. May be one of `EllipsizeNone`, `EllipsizeStart`, `EllipsizeMiddle` or `EllipsizeEnd`
  wrap: bool = false ## Enables/Disable wrapping of text.
  useMarkup: bool = false ## Determines whether to interpret the given text as Pango Markup or not.

  hooks:
    beforeBuild:
      state.internalWidget = gtk_label_new("")

  hooks text:
    property:
      if state.useMarkup:
        gtk_label_set_markup(state.internalWidget, state.text.cstring)
      else:
        gtk_label_set_text(state.internalWidget, state.text.cstring)
  
  hooks xAlign:
    property:
      gtk_label_set_xalign(state.internalWidget, state.xAlign.cdouble)
  
  hooks yAlign:
    property:
      gtk_label_set_yalign(state.internalWidget, state.yAlign.cdouble)
  
  hooks ellipsize:
    property:
      gtk_label_set_ellipsize(state.internalWidget, PangoEllipsizeMode(ord(state.ellipsize)))
  
  hooks wrap:
    property:
      gtk_label_set_wrap(state.internalWidget, cbool(ord(state.wrap)))
  
  hooks useMarkup:
    property:
      gtk_label_set_use_markup(state.internalWidget, cbool(ord(state.useMarkup)))
  
  example:
    Label:
      text = "Hello, world!"
      xAlign = 0.0
      ellipsize = EllipsizeEnd
  
  example:
    Label:
      text = "Test ".repeat(50)
      wrap = true
  
  example:
    Label:
      text = "<b>Bold</b>, <i>Italic</i>, <span font=\"20\">Font Size</span>"
      useMarkup = true

renderable EditableLabel of BaseWidget:
  text: string = ""
  editing: bool = false ## Determines whether the edit view (editing = false) or the "read" view (editing = true) is being shown
  enableUndo: bool = true
  alignment: 0.0..1.0 = 0.0
  
  proc changed(text: string) ## Fired every time `text` changes.
  proc editStateChanged(newEditState: bool) ## Fired every time `editing` changes.
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_editable_label_new("".cstring)
    connectEvents:
      proc changedCallback(widget: GtkWidget, data: ptr EventObj[proc (text: string)]) {.cdecl.} =
        let text = $gtk_editable_get_text(widget)
        EditableLabelState(data[].widget).text = text
        data[].callback(text)
        data[].redraw()
      
      proc editedCallback(widget: GtkWidget, pspec: GtkParamSpec, data: ptr EventObj[proc (newEditState: bool)]){.cdecl.} =
        let isEditing = gtk_editable_label_get_editing(widget).bool
        EditableLabelState(data[].widget).editing = isEditing
        data[].callback(isEditing)
        data[].redraw()
        
      state.connect(state.changed, "changed", changedCallback)
      state.connect(state.editStateChanged, "notify::editing", editedCallback)

    disconnectEvents:
      state.internalWidget.disconnect(state.changed)
      state.internalWidget.disconnect(state.editStateChanged)
  
  hooks text:
    property:
      gtk_editable_set_text(state.internalWidget, state.text.cstring)

  hooks editing:
    property:
      if state.editing:
        gtk_editable_label_start_editing(state.internalWidget)
      else:
        gtk_editable_label_stop_editing(state.internalWidget, cbool(true))

  hooks enableUndo:
    property:
      gtk_editable_set_enable_undo(state.internalWidget, state.enableUndo.cbool)
    
  hooks alignment:
    property:
      gtk_editable_set_alignment(state.internalWidget, state.alignment.cfloat)

renderable Icon of BaseWidget:
  name: string ## See [recommended_tools.md](recommended_tools.md#icons) for a list of icons.
  pixelSize: int = -1 ## Determines the size of the icon
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_image_new()
  
  hooks name:
    property:
      gtk_image_set_from_icon_name(state.internalWidget, state.name.cstring, GTK_ICON_SIZE_BUTTON)
  
  hooks pixelSize:
    property:
      gtk_image_set_pixel_size(state.internalWidget, state.pixelSize.cint)
  
  example:
    Icon:
      name = "list-add-symbolic"
  
  example:
    Icon:
      name = "object-select-symbolic"
      pixelSize = 100

type
  Colorspace* = enum
    ColorspaceRgb
  
  # Wrapper for the GdkPixbuf pointer to work with destructors of nim's ARC/ORC
  # Todo: As of 16.09.2023 it is mildly buggy to try and to `PixBuf = distinct GdkPixbuf` and
  # have destructors act on that new type directly. It was doable as shown in Ticket #75 and Github PR #81
  # But required a =sink hook for no understandable reason *and* seemed risky due to bugs likely making it unstable.
  # The pointer wrapped by intermediate type used as ref-type via an alias approach seems more stable for now.
  # Re-evaluate this in Match 2024 to see whether we can remove the wrapper obj.
  PixbufObj* = object
    gdk: GdkPixbuf
    
  Pixbuf* = ref PixbufObj

crossVersionDestructor(pixbuf, PixbufObj):
  if isNil(pixbuf.gdk):
    return
  
  g_object_unref(pointer(pixbuf.gdk))

proc `=copy`*(dest: var PixbufObj, source: PixbufObj) =
  let areSameObject = pointer(source.gdk) == pointer(dest.gdk)
  if areSameObject:
    return
  
  `=destroy`(dest)
  wasMoved(dest)
  if not isNil(source.gdk):
    g_object_ref(pointer(source.gdk))
    
  dest.gdk = source.gdk
    
proc newPixbuf(gdk: GdkPixbuf): Pixbuf =
  if gdk.isNil:
    raise newException(ValueError, "Unable to create Pixbuf from GdkPixbuf(nil)")

  result = Pixbuf(gdk: gdk)
  
proc newPixbuf*(width, height: int,
                bitsPerSample: int = 8,
                hasAlpha: bool = false,
                colorspace: Colorspace = ColorspaceRgb): Pixbuf =
  result = newPixbuf(gdk_pixbuf_new(
    GdkColorspace(ord(colorspace)),
    cbool(ord(hasAlpha)),
    bitsPerSample.cint,
    width.cint,
    height.cint
  ))

proc newPixbuf*(width, height: int,
                data: openArray[uint8],
                bitsPerSample: int = 8,
                hasAlpha: bool = false,
                colorspace: Colorspace = ColorspaceRgb): Pixbuf =
  let channels = if hasAlpha: 4 else: 3
  assert width * height * channels * (bitsPerSample div 8) == data.len
  
  proc destroy(pixels: pointer, data: pointer) {.cdecl.} =
    dealloc(pixels)
  
  let buffer = cast[ptr UncheckedArray[uint8]](alloc(data.len))
  if data.len > 0:
    copyMem(buffer, data[0].unsafeAddr, data.len)
  
  result = newPixbuf(gdk_pixbuf_new_from_data(
    buffer,
    GdkColorspace(ord(colorspace)),
    cbool(ord(hasAlpha)),
    bitsPerSample.cint,
    width.cint,
    height.cint,
    cint(channels * width * (bitsPerSample div 8)),
    destroy,
    nil
  ))

proc loadPixbuf*(path: string): Pixbuf =
  var error = GError(nil)
  let pixbuf = gdk_pixbuf_new_from_file(path.cstring, error.addr)
  if not error.isNil:
    let message = $error[].message
    raise newException(IoError, "Unable to load pixbuf: " & message)
  
  result = newPixbuf(pixbuf)

proc loadPixbuf*(path: string,
                 width, height: int,
                 preserveAspectRatio: bool = false): Pixbuf =
  var error = GError(nil)
  let pixbuf = gdk_pixbuf_new_from_file_at_scale(
    path.cstring,
    width.cint,
    height.cint,
    cbool(ord(preserveAspectRatio)),
    error.addr
  )
  if not error.isNil:
    let message = $error[].message
    raise newException(IoError, "Unable to load pixbuf: " & message)
  
  result = newPixbuf(pixbuf)

proc openInputStream(path: string): GInputStream =
  let file = g_file_new_for_path(path.cstring)
  var error = GError(nil)
  result = g_file_read(file, nil, error.addr)
  if not error.isNil:
    let message = $error[].message
    raise newException(IoError, "Unable to load pixbuf: " & message)

proc handlePixbufReady(stream: pointer, result: GAsyncResult, data: pointer) {.cdecl.} =
  let future = unwrapSharedCell(cast[ptr Future[Pixbuf]](data))
  
  var error = GError(nil)
  let pixbuf = gdk_pixbuf_new_from_stream_finish(result, error.addr)
  if error.isNil:
    future.complete(newPixbuf(pixbuf))
  else:
    let message = $error[].message
    future.fail(newException(IoError, "Unable to load pixbuf: " & message))
  
  if not stream.isNil:
    var error = GError(nil)
    discard g_input_stream_close(GInputStream(stream), nil, error.addr)
    if not error.isNil:
      let message = $error[].message
      raise newException(IoError, "Unable to close stream: " & message)
    g_object_unref(stream)

proc loadPixbufAsync*(path: string): Future[Pixbuf] =
  result = newFuture[Pixbuf]("loadPixbufAsync")
  let
    stream = openInputStream(path)
    data = allocSharedCell(result)
  gdk_pixbuf_new_from_stream_async(stream, nil, handlePixbufReady, data)

proc loadPixbufAsync*(path: string,
                      width, height: int,
                      preserveAspectRatio: bool = false): Future[Pixbuf] =
  result = newFuture[Pixbuf]("loadPixbufAsync")
  gdk_pixbuf_new_from_stream_at_scale_async(
    openInputStream(path),
    width.cint,
    height.cint,
    cbool(ord(preserveAspectRatio)),
    nil,
    handlePixbufReady,
    allocSharedCell(result)
  )

proc bitsPerSample*(pixbuf: Pixbuf): int =
  result = int(gdk_pixbuf_get_bits_per_sample(pixbuf.gdk))

proc width*(pixbuf: Pixbuf): int =
  result = int(gdk_pixbuf_get_width(pixbuf.gdk))

proc height*(pixbuf: Pixbuf): int =
  result = int(gdk_pixbuf_get_height(pixbuf.gdk))

proc channels*(pixbuf: Pixbuf): int =
  result = int(gdk_pixbuf_get_n_channels(pixbuf.gdk))

proc hasAlpha*(pixbuf: Pixbuf): bool =
  result = gdk_pixbuf_get_has_alpha(pixbuf.gdk) != 0

proc pixels*(pixbuf: Pixbuf): seq[byte] =
  let size = gdk_pixbuf_get_byte_length(pixbuf.gdk)
  result = newSeq[byte](size)
  if size > 0:
    let data = gdk_pixbuf_read_pixels(pixbuf.gdk)
    copyMem(result[0].addr, data, size)

proc flipVertical*(pixbuf: Pixbuf): Pixbuf =
  result = newPixbuf(gdk_pixbuf_flip(pixbuf.gdk, 0))

proc flipHorizontal*(pixbuf: Pixbuf): Pixbuf =
  result = newPixbuf(gdk_pixbuf_flip(pixbuf.gdk, 1))

proc crop*(pixbuf: Pixbuf, x, y, w, h: int): Pixbuf =
  let dest = gdk_pixbuf_new(
    gdk_pixbuf_get_colorspace(pixbuf.gdk),
    gdk_pixbuf_get_has_alpha(pixbuf.gdk),
    gdk_pixbuf_get_bits_per_sample(pixbuf.gdk),
    w.cint,
    h.cint
  )
  gdk_pixbuf_copy_area(
    pixbuf.gdk, x.cint, y.cint, w.cint, h.cint,
    dest, 0, 0
  )
  result = newPixbuf(dest)

proc scale*(pixbuf: Pixbuf, w, h: int, bilinear: bool = false): Pixbuf =
  var interp = GDK_INTERP_NEAREST
  if bilinear:
    interp = GDK_INTERP_BILINEAR
  result = newPixbuf(gdk_pixbuf_scale_simple(
    pixbuf.gdk, w.cint, h.cint, interp
  ))

proc rotate90*(pixbuf: Pixbuf): Pixbuf =
  result = newPixbuf(gdk_pixbuf_rotate_simple(
    pixbuf.gdk, GDK_PIXBUF_ROTATE_COUNTERCLOCKWISE
  ))

proc rotate180*(pixbuf: Pixbuf): Pixbuf =
  result = newPixbuf(gdk_pixbuf_rotate_simple(
    pixbuf.gdk, GDK_PIXBUF_ROTATE_UPSIDEDOWN
  ))

proc rotate270*(pixbuf: Pixbuf): Pixbuf =
  result = newPixbuf(gdk_pixbuf_rotate_simple(
    pixbuf.gdk, GDK_PIXBUF_ROTATE_CLOCKWISE
  ))

proc save*(pixbuf: Pixbuf,
           path: string,
           fileType: string,
           options: openArray[(string, string)] = []) =
  var
    keys: seq[string] = @[]
    values: seq[string] = @[]
  for (key, value) in options:
    keys.add(key)
    values.add(value)
  
  let
    keysArray = allocCStringArray(keys)
    valuesArray = allocCStringArray(values)
  defer:
    deallocCStringArray(keysArray)
    deallocCStringArray(valuesArray)
  
  var error = GError(nil)
  discard gdk_pixbuf_savev(pixbuf.gdk,
    path.cstring,
    fileType.cstring,
    keysArray,
    valuesArray,
    error.addr
  )
  if not error.isNil:
    let message = $error[].message
    raise newException(IoError, "Unable to save pixbuf: " & message)

type ContentFit* = enum
  ContentFill
  ContentContain
  ContentCover
  ContentScaleDown

renderable Picture of BaseWidget:
  pixbuf: Pixbuf
  contentFit: ContentFit = ContentContain ## Requires GTK 4.8 or higher to fully work, compile with `-d:gtkminor=8` to enable
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_picture_new()
  
  hooks pixbuf:
    property:
      gtk_picture_set_pixbuf(state.internalWidget, state.pixbuf.gdk)
  
  hooks contentFit:
    property:
      when GtkMinor >= 8:
        gtk_picture_set_content_fit(state.internalWidget, GtkContentFit(ord(state.contentFit)))
      else:
        gtk_picture_set_keep_aspect_ratio(
          state.internalWidget,
          cbool(ord(state.contentFit != ContentFill))
        )

const
  ButtonSuggested* = "suggested-action".StyleClass
  ButtonDestructive* = "destructive-action".StyleClass
  ButtonFlat* = "flat".StyleClass
  ButtonPill* = "pill".StyleClass
  ButtonCircular* = "circular".StyleClass

renderable Button of BaseWidget:
  child: Widget
  shortcut: string ## Keyboard shortcut
  
  proc clicked()
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_button_new()
    connectEvents:
      state.connect(state.clicked, "clicked", eventCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.clicked)
  
  hooks shortcut:
    build:
      if widget.hasShortcut:
        state.shortcut = widget.valShortcut
      if state.shortcut.len > 0: 
        let
          trigger = gtk_shortcut_trigger_parse_string(state.shortcut.cstring)
          action = gtk_shortcut_action_parse_string("signal(clicked)")
          shortcut = gtk_shortcut_new(trigger, action)
          controller = gtk_shortcut_controller_new()
        gtk_shortcut_controller_set_scope(controller, GTK_SHORTCUT_SCOPE_MANAGED)
        gtk_shortcut_controller_add_shortcut(controller, shortcut)
        gtk_widget_add_controller(state.internalWidget, controller)
    update:
      if widget.hasShortcut:
        assert state.shortcut == widget.valShortcut # TODO

  hooks child:
    (build, update):
      state.updateChild(state.child, widget.valChild, gtk_button_set_child)
  
  setter text: string
  setter icon: string ## Sets the icon of the Button (see [recommended_tools.md](recommended_tools.md#icons) for a list of icons)
  
  adder add:
    if widget.hasChild:
      raise newException(ValueError, "Unable to add multiple children to a Button. Use a Box widget to display multiple widgets in a Button.")
    widget.hasChild = true
    widget.valChild = child
  
  example:
    Button:
      icon = "list-add-symbolic"
      style = [ButtonSuggested]
      proc clicked() =
        echo "clicked"
  
  example:
    Button:
      text = "Delete"
      style = [ButtonDestructive]
  
  example:
    Button:
      text = "Inactive Button"
      sensitive = false
  
  example:
    Button:
      text = "Copy"
      shortcut = "<Ctrl>C"
      proc clicked() =
        app.writeClipboard("Hello, world!")


proc `hasText=`*(button: Button, value: bool) = button.hasChild = value
proc `valText=`*(button: Button, value: string) =
  button.valChild = Label(hasText: true, valText: value)

proc `hasIcon=`*(button: Button, value: bool) = button.hasChild = value
proc `valIcon=`*(button: Button, name: string) =
  button.valChild = Icon(hasName: true, valName: name)

proc updateChild*(state: Renderable,
                  child: var BoxChild[WidgetState],
                  updater: BoxChild[Widget],
                  setChild: proc(widget, child: GtkWidget) {.cdecl, locker.}) =
  if updater.widget.isNil:
    if not child.widget.isNil:
      child.widget = nil
      setChild(state.internalWidget, nil.GtkWidget)
  else:
    updater.assignApp(state.app)
    let newChild =
      if child.widget.isNil:
        updater.widget.build()
      else:
        updater.widget.update(child.widget)
    
    if not newChild.isNil:
      child.widget = newChild
      setChild(state.internalWidget, unwrapInternalWidget(child.widget))
    
    let childWidget = unwrapInternalWidget(child.widget)
    
    if not newChild.isNil or updater.hAlign != child.hAlign:
      child.hAlign = updater.hAlign
      gtk_widget_set_halign(childWidget, toGtk(child.hAlign))
    
    if not newChild.isNil or updater.vAlign != child.vAlign:
      child.vAlign = updater.vAlign
      gtk_widget_set_valign(childWidget, toGtk(child.vAlign))
    
    if not newChild.isNil or updater.expand != child.expand:
      child.expand = updater.expand
      gtk_widget_set_hexpand(childWidget, child.expand.ord.cbool)

type WindowControlButton* = enum
  WindowControlMinimize = "minimize"
  WindowControlMaximize = "maximize"
  WindowControlClose = "close"
  WindowControlIcon = "icon"
  WindowControlMenu = "menu"

type DecorationLayout* = tuple[left: seq[WindowControlButton], right: seq[WindowControlButton]]

proc toLayoutString*(layout: DecorationLayout): string =
  let leftButtons: string = layout.left.mapIt($it).join(",")
  let rightButtons: string = layout.right.mapIt($it).join(",")
  return fmt"{leftButtons}:{rightButtons}"

renderable HeaderBar of BaseWidget:
  title: BoxChild[Widget]
  showTitleButtons: bool = true
  decorationLayout: Option[string] = none(string)
  left: seq[Widget]
  right: seq[Widget]
  
  setter windowControls: DecorationLayout
  setter windowControls: Option[DecorationLayout]
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_header_bar_new()
  
  hooks showTitleButtons:
    property:
      gtk_header_bar_set_show_title_buttons(state.internalWidget, cbool(ord(state.showTitleButtons)))
  
  hooks decorationLayout:
    property:
      if state.decorationLayout.isSome():
        gtk_header_bar_set_decoration_layout(state.internalWidget, state.decorationLayout.get().cstring)
      else:
        gtk_header_bar_set_decoration_layout(state.internalWidget, nil)

  hooks left:
    (build, update):
      state.updateChildren(
        state.left,
        widget.valLeft,
        gtk_header_bar_pack_start,
        gtk_header_bar_remove
      )
  
  hooks right:
    (build, update):
      state.updateChildren(
        state.right,
        widget.valRight,
        gtk_header_bar_pack_end,
        gtk_header_bar_remove
      )
  
  hooks title:
    (build, update):
      state.updateChild(state.title, widget.valTitle, gtk_header_bar_set_title_widget)
  
  adder addTitle {.expand: false,
                   hAlign: AlignFill,
                   vAlign: AlignFill.}:
    ## Adds a custom title widget to the HeaderBar.
    ## When expand is true, it grows to fill up the remaining space in the headerbar.
    ## The `hAlign` and `vAlign` properties allow you to set the horizontal and vertical 
    ## alignment of the child within its allocated area. They may be one of `AlignFill`, 
    ## `AlignStart`, `AlignEnd` or `AlignCenter`.
    if widget.hasTitle:
      raise newException(ValueError, "Unable to add multiple title widgets to a HeaderBar.")
    widget.hasTitle = true
    widget.valTitle = BoxChild[Widget](
      widget: child,
      expand: expand,
      hAlign: hAlign,
      vAlign: vAlign
    )
  
  adder addLeft:
    ## Adds a widget to the left side of the HeaderBar.
    widget.hasLeft = true
    widget.valLeft.add(child)
  
  adder addRight:
    ## Adds a widget to the right side of the HeaderBar.
    widget.hasRight = true
    widget.valRight.add(child)
  
  
  example:
    Window:
      title = "Title"
      
      HeaderBar {.addTitlebar.}:
        Button {.addLeft.}:
          icon = "list-add-symbolic"
        
        Button {.addRight.}:
          icon = "open-menu-symbolic"

proc `hasWindowControls=`*(widget: Headerbar, has: bool) =
  widget.hasDecorationLayout = true

proc `valWindowControls=`*(widget: Headerbar, buttons: DecorationLayout) =
  widget.valDecorationLayout = some(buttons.toLayoutString())

proc `valWindowControls=`*(widget: Headerbar, buttons: Option[DecorationLayout]) =
  let decorationLayout: Option[string] = buttons.map(controls => controls.toLayoutString())
  widget.valDecorationLayout = decorationLayout
  
renderable ScrolledWindow of BaseWidget:
  child: Widget
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_scrolled_window_new(nil.GtkAdjustment, nil.GtkAdjustment)
  
  hooks child:
    (build, update):
      state.updateChild(state.child, widget.valChild, gtk_scrolled_window_set_child)
  
  adder add:
    if widget.hasChild:
      raise newException(ValueError, "Unable to add multiple children to a ScrolledWindow. Use a Box widget to display multiple widgets in a ScrolledWindow.")
    widget.hasChild = true
    widget.valChild = child

const
  EntrySuccess* = "success".StyleClass
  EntryWarning* = "warning".StyleClass
  EntryError* = "error".StyleClass

renderable Entry of BaseWidget:
  text: string
  placeholder: string ## Shown when the Entry is empty.
  width: int = -1
  maxWidth: int = -1
  xAlign: float = 0.0
  visibility: bool = true
  invisibleChar: Rune = '*'.Rune

  proc changed(text: string) ## Called when the text in the Entry changed
  proc activate() ## Called when the user presses enter/return

  hooks:
    beforeBuild:
      state.internalWidget = gtk_entry_new()
    connectEvents:
      proc changedCallback(widget: GtkWidget, data: ptr EventObj[proc (text: string)]) {.cdecl.} =
        let text = $gtk_editable_get_text(widget)
        EntryState(data[].widget).text = text
        data[].callback(text)
        data[].redraw()
      
      state.connect(state.changed, "changed", changedCallback)
      state.connect(state.activate, "activate", eventCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.changed)
      state.internalWidget.disconnect(state.activate)

  hooks text:
    property:
      gtk_editable_set_text(state.internalWidget, state.text.cstring)
    read:
      state.text = $gtk_editable_get_text(state.internalWidget)
  
  hooks placeholder:
    property:
      gtk_entry_set_placeholder_text(state.internalWidget, state.placeholder.cstring)
  
  hooks width:
    property:
      gtk_editable_set_width_chars(state.internalWidget, state.width.cint)
  
  hooks maxWidth:
    property:
      gtk_editable_set_max_width_chars(state.internalWidget, state.maxWidth.cint)
  
  hooks xAlign:
    property:
      gtk_entry_set_alignment(state.internalWidget, state.xAlign.cfloat)

  hooks visibility:
    property:
      gtk_entry_set_visibility(state.internalWidget, cbool(ord(state.visibility)))

  hooks invisibleChar:
    property:
      gtk_entry_set_invisible_char(state.internalWidget, state.invisibleChar.uint32)

  
  example:
    Entry:
      text = app.text
      proc changed(text: string) =
        app.text = text
  
  example:
    Entry:
      text = app.query
      placeholder = "Search..."
      proc changed(query: string) =
        app.query = query
      proc activate() =
        ## Runs when enter is pressed
        echo app.query
  
  example:
    Entry:
      placeholder = "Password"
      visibility = false
      invisibleChar = '*'.Rune

renderable Spinner of BaseWidget:
  spinning: bool

  hooks:
    beforeBuild:
      state.internalWidget = gtk_spinner_new()

  hooks spinning:
    property:
      gtk_spinner_set_spinning(state.internalWidget, cbool(ord(state.spinning)))

renderable SpinButton of BaseWidget:
  ## Entry for entering numeric values
  
  digits: uint = 1 ## Number of digits
  climbRate: float = 0.1
  wrap: bool ## When the maximum (minimum) value is reached, the SpinButton will wrap around to the minimum (maximum) value.
  min: float = 0.0 ## Lower bound
  max: float = 100.0 ## Upper bound
  stepIncrement: float = 0.1
  pageIncrement: float = 1
  pageSize: float = 0
  value: float
  
  proc valueChanged(value: float)
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_spin_button_new(
        GtkAdjustment(nil),
        cdouble(widget.valClimbRate),
        cuint(widget.valDigits)
      )
    connectEvents:
      proc valueChangedCallback(widget: GtkWidget, data: ptr EventObj[proc (value: float)]) {.cdecl.} =
        let value = float(gtk_spin_button_get_value(widget))
        SpinButtonState(data[].widget).value = value
        data[].callback(value)
        data[].redraw()
      
      state.connect(state.valueChanged, "value-changed", valueChangedCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.valueChanged)
  
  hooks digits:
    property:
      gtk_spin_button_set_digits(state.internalWidget, cuint(state.digits))
  
  hooks climbRate:
    property:
      gtk_spin_button_set_climb_rate(state.internalWidget, cdouble(state.climbRate))
  
  hooks wrap:
    property:
      gtk_spin_button_set_wrap(state.internalWidget, cbool(ord(state.wrap)))
  
  hooks min:
    property:
      let adjustment = gtk_spin_button_get_adjustment(state.internalWidget)
      gtk_adjustment_set_lower(adjustment, cdouble(state.min))
  
  hooks max:
    property:
      let adjustment = gtk_spin_button_get_adjustment(state.internalWidget)
      gtk_adjustment_set_upper(adjustment, cdouble(state.max))
  
  hooks stepIncrement:
    property:
      let adjustment = gtk_spin_button_get_adjustment(state.internalWidget)
      gtk_adjustment_set_step_increment(adjustment, cdouble(state.stepIncrement))
  
  hooks pageIncrement:
    property:
      let adjustment = gtk_spin_button_get_adjustment(state.internalWidget)
      gtk_adjustment_set_page_increment(adjustment, cdouble(state.pageIncrement))
  
  hooks pageSize:
    property:
      let adjustment = gtk_spin_button_get_adjustment(state.internalWidget)
      gtk_adjustment_set_page_size(adjustment, cdouble(state.pageSize))
  
  hooks value:
    property:
      gtk_spin_button_set_value(state.internalWidget, cdouble(state.value))
    read:
      state.value = float(gtk_spin_button_get_value(state.internalWidget))
  
  example:
    SpinButton:
      value = app.value
      
      proc valueChanged(value: float) =
        app.value = value

type PanedChild[T] = object
  widget: T
  resize: bool
  shrink: bool

proc buildPanedChild(child: PanedChild[Widget],
                     app: Viewable,
                     internalWidget: GtkWidget,
                     setChild: proc(paned, child: GtkWidget) {.cdecl, locker.},
                     setResize: proc(paned: GtkWidget, val: cbool) {.cdecl, locker.},
                     setShrink: proc(paned: GtkWidget, val: cbool) {.cdecl, locker.}): PanedChild[WidgetState] =
  child.widget.assignApp(app)
  result = PanedChild[WidgetState](
    widget: child.widget.build(),
    resize: child.resize,
    shrink: child.shrink
  )
  setChild(internalWidget, result.widget.unwrapInternalWidget())
  setResize(internalWidget, cbool(ord(child.resize)))
  setShrink(internalWidget, cbool(ord(child.shrink)))

proc updatePanedChild(state: var PanedChild[WidgetState],
                      target: PanedChild[Widget],
                      app: Viewable) =
  target.widget.assignApp(app)
  assert target.resize == state.resize
  assert target.shrink == state.shrink
  let newChild = target.widget.update(state.widget)
  assert newChild.isNil


renderable Paned of BaseWidget:
  orient: Orient ## Orientation of the panes
  initialPosition: int ## Initial position of the separator in pixels
  first: PanedChild[Widget]
  second: PanedChild[Widget]
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_paned_new(toGtk(widget.valOrient))
      state.orient = widget.valOrient
  
  hooks first:
    build:
      if widget.hasFirst:
        state.first = widget.valFirst.buildPanedChild(
          state.app, state.internalWidget,
          gtk_paned_set_start_child,
          gtk_paned_set_resize_start_child,
          gtk_paned_set_shrink_start_child
        )
    update:
      if widget.hasFirst:
        state.first.updatePanedChild(widget.valFirst, state.app)

  hooks initialPosition:
    build:
      if widget.hasInitialPosition:
        state.initialPosition = widget.valInitialPosition
        gtk_paned_set_position(state.internalWidget, cint(state.initialPosition))
  
  hooks second:
    build:
      if widget.hasSecond:
        state.second = widget.valSecond.buildPanedChild(
          state.app, state.internalWidget,
          gtk_paned_set_end_child,
          gtk_paned_set_resize_end_child,
          gtk_paned_set_shrink_end_child
        )
    update:
      if widget.hasSecond:
        state.second.updatePanedChild(widget.valSecond, state.app)
  
  adder add {.resize: true, shrink: false.}:
    let panedChild = PanedChild[Widget](
      widget: child,
      resize: resize,
      shrink: shrink
    )
    if widget.hasFirst:
      widget.hasSecond = true
      widget.valSecond = panedChild
    else:
      widget.hasFirst = true
      widget.valFirst = panedChild
  
  example:
    Paned:
      initialPosition = 200
      Box(orient = OrientY) {.resize: false.}:
        Label(text = "Sidebar")
      Box(orient = OrientY) {.resize: true.}:
        Label(text = "Content")

type
  ModifierKey* = enum
    ModifierCtrl, ModifierAlt, ModifierShift,
    ModifierSuper, ModifierMeta, ModifierHyper
  
  ButtonEvent* = object
    time*: uint32
    button*: int
    x*, y*: float
    modifiers*: set[ModifierKey]
  
  MotionEvent* = object
    time*: uint32
    x*, y*: float
    modifiers*: set[ModifierKey]
  
  KeyEvent* = object
    time*: uint32
    rune*: Rune
    value*: int
    modifiers*: set[ModifierKey]
  
  ScrollDirection* = enum
    ScrollUp, ScrollDown, ScrollLeft, ScrollRight, ScrollSmooth
  
  ScrollEvent* = object
    time*: uint32
    modifiers*: set[ModifierKey]
    case direction*: ScrollDirection:
      of ScrollSmooth: dx*, dy*: float
      else: discard

proc toScrollDirection(dir: GdkScrollDirection): ScrollDirection =
  result = ScrollDirection(ord(dir))

proc initModifierSet(state: GdkModifierType): set[ModifierKey] =
  const MODIFIERS = [
    (GDK_CONTROL_MASK, ModifierCtrl),
    (GDK_ALT_MASK, ModifierAlt),
    (GDK_SHIFT_MASK, ModifierShift),
    (GDK_SUPER_MASK, ModifierSuper),
    (GDK_HYPER_MASK, ModifierHyper)
  ]
  for (mask, key) in MODIFIERS:
    if mask in state:
      result.incl(key)

type
  CustomWidgetEventsObj = object
    mousePressed: proc(event: ButtonEvent): bool
    mouseReleased: proc(event: ButtonEvent): bool
    mouseMoved: proc(event: MotionEvent): bool
    scroll: proc(event: ScrollEvent): bool
    keyPressed: proc(event: KeyEvent): bool
    keyReleased: proc(event: KeyEvent): bool
    app: Viewable
  
  CustomWidgetEvents = ref CustomWidgetEventsObj

proc gdkEventCallback(controller: GtkEventController, event: GdkEvent, data: ptr CustomWidgetEventsObj): cbool =
  let
    modifiers = initModifierSet(gdk_event_get_modifier_state(event))
    time = gdk_event_get_time(event)
    pos = block:
      var nativePos = (x: cdouble(0.0), y: cdouble(0.0))
      discard gdk_event_get_position(event, nativePos.x.addr, nativePos.y.addr)
      
      let
        widget = gtk_event_controller_get_widget(controller)
        root = gtk_widget_get_root(widget)
        native = gtk_widget_get_native(root)
      
      var nativeOffset = (x: cdouble(0.0), y: cdouble(0.0))
      gtk_native_get_surface_transform(native, nativeOffset.x.addr, nativeOffset.y.addr)
      
      var localPos = (x: cdouble(0.0), y: cdouble(0.0))
      discard gtk_widget_translate_coordinates(
        root, widget,
        nativePos.x - nativeOffset.x, nativePos.y - nativeOffset.y,
        localPos.x.addr, localPos.y.addr
      )
      localPos
  
  var
    stopEvent = false
    requiresRedraw = false
  
  let kind = gdk_event_get_event_type(event)
  case kind:
    of GDK_MOTION_NOTIFY:
      if not data[].mouseMoved.isNil:
        stopEvent = data[].mouseMoved(MotionEvent(
          time: time,
          x: float(pos.x),
          y: float(pos.y),
          modifiers: modifiers
        ))
        requiresRedraw = true
    of GDK_BUTTON_PRESS, GDK_BUTTON_RELEASE:
      let evt = ButtonEvent(
        time: time,
        button: int(gdk_button_event_get_button(event)) - 1,
        x: float(pos.x),
        y: float(pos.y),
        modifiers: modifiers
      )
      if kind == GDK_BUTTON_PRESS:
        if not data[].mousePressed.isNil:
          stopEvent = data[].mousePressed(evt)
          requiresRedraw = true
      else:
        if not data[].mouseReleased.isNil:
          stopEvent = data[].mouseReleased(evt)
          requiresRedraw = true
    of GDK_KEY_PRESS, GDK_KEY_RELEASE:
      let
        keyVal = gdk_key_event_get_keyval(event)
        evt = KeyEvent(
          time: time,
          rune: Rune(gdk_keyval_to_unicode(keyVal)),
          value: keyVal.int,
          modifiers: modifiers
        )
      if kind == GDK_KEY_PRESS:
        if not data[].keyPressed.isNil:
          stopEvent = data[].keyPressed(evt)
          requiresRedraw = true
      else:
        if not data[].keyReleased.isNil:
          stopEvent = data[].keyReleased(evt)
          requiresRedraw = true
    of GDK_SCROLL:
      if not data[].scroll.isNil:
        var evt = ScrollEvent(
          time: time,
          direction: toScrollDirection(gdk_scroll_event_get_direction(event)),
          modifiers: modifiers
        )
        if evt.direction == ScrollSmooth:
          var
            dx: cdouble
            dy: cdouble
          gdk_scroll_event_get_deltas(event, dx.addr, dy.addr)
          evt.dx = float(dx)
          evt.dy = float(dy)
        stopEvent = data[].scroll(evt)
        requiresRedraw = true
    else: discard
  
  if requiresRedraw:
    if data[].app.isNil:
      raise newException(ValueError, "App is nil")
    discard data[].app.redraw()
  result = cbool(ord(stopEvent))

proc drawFunc(widget: GtkWidget,
              ctx: pointer,
              width, height: cint,
              data: pointer) {.cdecl.} =
  let
    event = cast[ptr EventObj[proc (ctx: CairoContext, size: (int, int)): bool]](data)
    requiresRedraw = event[].callback(CairoContext(ctx), (int(width), int(height)))
  if requiresRedraw:
    event[].redraw()

proc callbackOrNil[T](event: Event[T]): T =
  if event.isNil:
    result = nil
  else:
    result = event.callback

renderable CustomWidget of BaseWidget:
  focusable: bool
  events {.private, onlyState.}: CustomWidgetEvents
  
  proc mousePressed(event: ButtonEvent): bool
  proc mouseReleased(event: ButtonEvent): bool
  proc mouseMoved(event: MotionEvent): bool
  proc scroll(event: ScrollEvent): bool
  proc keyPressed(event: KeyEvent): bool
  proc keyReleased(event: KeyEvent): bool
  
  hooks:
    build:
      state.events = CustomWidgetEvents()
      let controller = gtk_event_controller_legacy_new()
      discard g_signal_connect(controller, "event", gdkEventCallback, state.events[].addr)
      gtk_widget_add_controller(state.internalWidget, controller)
      # TODO: Check memory safety
    connectEvents:
      state.events.app = state.app
      state.events.mousePressed = state.mousePressed.callbackOrNil
      state.events.mouseReleased = state.mouseReleased.callbackOrNil
      state.events.mouseMoved = state.mouseMoved.callbackOrNil
      state.events.scroll = state.scroll.callbackOrNil
      state.events.keyPressed = state.keyPressed.callbackOrNil
      state.events.keyReleased = state.keyReleased.callbackOrNil
  
  hooks focusable:
    property:
      gtk_widget_set_can_focus(state.internalWidget, cbool(ord(state.focusable)))

renderable DrawingArea of CustomWidget:
  ## Allows you to render 2d scenes using cairo.
  ## The `owlkettle/cairo` module provides bindings for cairo.
  
  proc draw(ctx: CairoContext, size: (int, int)): bool ## Called when the widget is rendered. Redraws the application if the callback returns true.
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_drawing_area_new()
    connectEvents:
      gtk_drawing_area_set_draw_func(state.internalWidget, draw_func, state.draw[].addr, nil)
    update:
      gtk_widget_queue_draw(state.internalWidget)
  
  example:
    DrawingArea:
      ## You need to import the owlkettle/cairo module in order to use CairoContext
      proc draw(ctx: CairoContext, size: tuple[width, height: int]): bool =
        ctx.rectangle(100, 100, 300, 200)
        ctx.source = (0.0, 0.0, 0.0)
        ctx.stroke()

proc setupEventCallback(widget: GtkWidget, data: ptr EventObj[proc (size: (int, int)): bool]) =
  gtk_gl_area_make_current(widget)
  if not gtk_gl_area_get_error(widget).isNil:
    raise newException(IOError, "Failed to initialize OpenGL context")
  
  let
    width = int(gtk_widget_get_allocated_width(widget))
    height = int(gtk_widget_get_allocated_height(widget))
    requiresRedraw = data[].callback((width, height))
  if requiresRedraw:
    data[].redraw()

proc renderEventCallback(widget: GtkWidget,
                         context: pointer,
                         data: ptr EventObj[proc (size: (int, int)): bool]): cbool =
  let
    width = int(gtk_widget_get_allocated_width(widget))
    height = int(gtk_widget_get_allocated_height(widget))
    requiresRedraw = data[].callback((width, height))
  if requiresRedraw:
    data[].redraw()
  result = cbool(ord(true))

renderable GlArea of CustomWidget:
  ## Allows you to render 3d scenes using OpenGL.
  
  useEs: bool = false
  requiredVersion: tuple[major, minor: int] = (4, 3)
  hasDepthBuffer: bool = true
  hasStencilBuffer: bool = false
  
  proc setup(size: (int, int)): bool ## Called after the OpenGL Context is initialized. Redraws the application if the callback returns true.
  proc render(size: (int, int)): bool ## Called when the widget is rendered. Your rendering code should be executed here. Redraws the application if the callback returns true.
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_gl_area_new()
    connectEvents:
      state.connect(state.setup, "realize", setupEventCallback)
      state.connect(state.render, "render", renderEventCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.setup)
      state.internalWidget.disconnect(state.render)
    update:
      gtk_widget_queue_draw(state.internalWidget)
  
  hooks useEs:
    property:
      gtk_gl_area_set_use_es(state.internalWidget, cbool(ord(state.useEs)))
  
  hooks hasDepthBuffer:
    property:
      gtk_gl_area_set_has_depth_buffer(state.internalWidget, cbool(ord(state.hasDepthBuffer)))
  
  hooks hasStencilBuffer:
    property:
      gtk_gl_area_set_has_stencil_buffer(state.internalWidget, cbool(ord(state.hasStencilBuffer)))
  
  hooks requiredVersion:
    property:
      gtk_gl_area_set_required_version(state.internalWidget, 
        cint(state.requiredVersion.major),
        cint(state.requiredVersion.minor)
      )

renderable ColorButton of BaseWidget:
  color: tuple[r, g, b, a: float] = (0.0, 0.0, 0.0, 1.0) ## Red, Geen, Blue, Alpha as floating point numbers in the range [0.0, 1.0]
  useAlpha: bool = false
  
  proc changed(color: tuple[r, g, b, a: float])
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_color_button_new()
    connectEvents:
      proc colorSetCallback(widget: GtkWidget, data: ptr EventObj[proc (color: tuple[r, g, b, a: float])]) {.cdecl.} =
        var gdkColor: GdkRgba
        gtk_color_chooser_get_rgba(widget, gdkColor.addr)
        let color = (gdkColor.r.float, gdkColor.g.float, gdkColor.b.float, gdkColor.a.float)
        ColorButtonState(data[].widget).color = color
        data[].callback(color)
        data[].redraw()
      
      state.connect(state.changed, "color-set", colorSetCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.changed)
  
  hooks color:
    property:
      var rgba = GdkRgba(
        r: cdouble(state.color.r),
        g: cdouble(state.color.g),
        b: cdouble(state.color.b),
        a: cdouble(state.color.a)
      )
      gtk_color_chooser_set_rgba(state.internalWidget, rgba.addr)
  
  hooks useAlpha:
    property:
      gtk_color_chooser_set_use_alpha(state.internalWidget, cbool(ord(state.useAlpha)))


renderable Switch of BaseWidget:
  state: bool
  
  proc changed(state: bool)
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_switch_new()
    connectEvents:
      proc stateSetCallback(widget: GtkWidget, state: cbool, data: ptr EventObj[proc (state: bool)]): cbool {.cdecl.} =
        let state = state != 0
        SwitchState(data[].widget).state = state
        data[].callback(state)
        data[].redraw()
      
      state.connect(state.changed, "state-set", stateSetCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.changed)
  
  hooks state:
    property:
      gtk_switch_set_active(state.internalWidget, cbool(ord(state.state)))
  
  example:
    Switch:
      state = app.state
      proc changed(state: bool) =
        app.state = state

renderable ToggleButton of Button:
  state: bool
  
  proc changed(state: bool)
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_toggle_button_new()
    connectEvents:
      proc toggledCallback(widget: GtkWidget, data: ptr EventObj[proc (state: bool)]) {.cdecl.} =
        let state = gtk_toggle_button_get_active(widget) != 0
        ToggleButtonState(data[].widget).state = state
        data[].callback(state)
        data[].redraw()
      
      state.connect(state.changed, "toggled", toggledCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.changed)
  
  hooks state:
    property:
      gtk_toggle_button_set_active(state.internalWidget, cbool(ord(state.state)))
  
  example:
    ToggleButton:
      text = "Current State: " & $app.state
      state = app.state
      proc changed(state: bool) =
        app.state = state

renderable LinkButton of Button:
  ## A clickable link.
  
  uri: string
  visited: bool
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_link_button_new("")
  
  hooks uri:
    property:
      gtk_link_button_set_uri(state.internalWidget, cstring(state.uri))
  
  hooks visited:
    property:
      gtk_link_button_set_visited(state.internalWidget, cbool(ord(state.visited)))

renderable CheckButton of BaseWidget:
  state: bool
  
  proc changed(state: bool)
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_check_button_new()
    connectEvents:
      proc toggledCallback(widget: GtkWidget, data: ptr EventObj[proc (state: bool)]) {.cdecl.} =
        let state = gtk_check_button_get_active(widget) != 0
        CheckButtonState(data[].widget).state = state
        data[].callback(state)
        data[].redraw()
      
      state.connect(state.changed, "toggled", toggledCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.changed)
  
  hooks state:
    property:
      gtk_check_button_set_active(state.internalWidget, cbool(ord(state.state)))
  
  example:
    CheckButton:
      state = app.state
      proc changed(state: bool) =
        app.state = state

renderable RadioGroup of BaseWidget:
  ## A list of options selectable using radio buttons.
  
  spacing: int = 3 ## Spacing between the rows
  rowSpacing: int = 6 ## Spacing between the radio button and 
  orient: Orient = OrientY ## Orientation of the list
  children: seq[Widget]
  
  selected: int ## Currently selected index, may be smaller or larger than the number of children to represent no option being selected
  proc select(index: int)
  
  type
    RadioGroupRowDataObj = object
      ## Data used to handle the toggled signals of the row
      state: RadioGroupState
      index: int
    
    RadioGroupRowData = ref RadioGroupRowDataObj
    
    RadioGroupRow = object
      box: GtkWidget
      button: GtkWidget
      data: RadioGroupRowData
  
  rows {.private, onlyState.}: seq[RadioGroupRow]
  
  hooks:
    beforeBuild:
      let orient = if widget.hasOrient: widget.valOrient else: OrientY
      state.internalWidget = gtk_box_new(
        toGtk(orient),
        widget.valSpacing.cint
      )
  
  hooks spacing:
    property:
      gtk_box_set_spacing(state.internalWidget, state.spacing.cint)
  
  hooks rowSpacing:
    property:
      for row in state.rows:
        gtk_box_set_spacing(row.box, state.rowSpacing.cint)
  
  hooks orient:
    property:
      gtk_orientable_set_orientation(state.internalWidget, state.orient.toGtk())

  hooks children:
    (build, update):
      widget.valChildren.assignApp(state.app)
      
      var it = 0
      while it < state.children.len and it < widget.valChildren.len:
        let newChild = widget.valChildren[it].update(state.children[it])
        if not newChild.isNil:
          let childWidget = newChild.unwrapInternalWidget()
          gtk_widget_set_hexpand(childWidget, cbool(ord(true)))
          
          let box = state.rows[it].box
          gtk_box_remove(box, state.children[it].unwrapInternalWidget())
          gtk_box_append(box, childWidget)
          
          state.children[it] = newChild
        
        it += 1
      
      while it < widget.valChildren.len:
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, state.rowSpacing.cint)
        gtk_widget_set_hexpand(box, cbool(ord(true)))
        gtk_widget_set_vexpand(box, cbool(ord(true)))
        
        
        let radioButton = gtk_check_button_new()
        if it > 0:
          gtk_check_button_set_group(radioButton, state.rows[0].button)
        if it == state.selected:
          gtk_check_button_set_active(radioButton, cbool(ord(true)))
        
        let data = RadioGroupRowData(state: state, index: it)
        
        proc toggledCallback(widget: GtkWidget, data: ptr RadioGroupRowDataObj) =
          if gtk_check_button_get_active(widget) != 0 and
             data[].state.selected != data[].index:
            data[].state.selected = data[].index
            if not data[].state.select.isNil:
              data[].state.select.callback(data[].index)
              data[].state.select[].redraw()
        
        discard g_signal_connect(radioButton, "toggled", toggledCallback, data[].addr)
        
        gtk_box_append(box, radioButton)
        
        let
          child = widget.valChildren[it].build()
          childWidget = child.unwrapInternalWidget()
        state.children.add(child)
        gtk_widget_set_hexpand(childWidget, cbool(ord(true)))
        gtk_box_append(box, childWidget)
        
        gtk_box_append(state.internalWidget, box)
        
        state.rows.add(RadioGroupRow(
          box: box,
          button: radioButton,
          data: data
        ))
        
        it += 1
      
      while it < state.children.len:
        discard state.children.pop()
        gtk_box_remove(state.internalWidget, state.rows.pop().box)
  
  hooks selected:
    property:
      if state.selected in 0..<state.rows.len:
        gtk_check_button_set_active(state.rows[state.selected].button, cbool(ord(true)))
      else:
        for row in state.rows:
          gtk_check_button_set_active(row.button, cbool(ord(false)))
  
  adder add:
    widget.hasChildren = true
    widget.valChildren.add(child)
  
  example:
    RadioGroup:
      selected = app.selected
      
      proc select(index: int) =
        app.selected = index
      
      Label(text = "Option 0", xAlign = 0)
      Label(text = "Option 1", xAlign = 0)
      Label(text = "Option 2", xAlign = 0)

type PopoverPosition* = enum
  PopoverLeft
  PopoverRight
  PopoverTop
  PopoverBottom

proc toGtk(pos: PopoverPosition): GtkPositionType =
  result = GtkPositionType(ord(pos))

renderable BasePopover of BaseWidget:
  hasArrow: bool = true
  offset: tuple[x, y: int] = (0, 0)
  position: PopoverPosition = PopoverBottom
  
  hooks hasArrow:
    property:
      gtk_popover_set_has_arrow(state.internalWidget, cbool(ord(state.hasArrow)))
  
  hooks offset:
    property:
      gtk_popover_set_offset(state.internalWidget,
        cint(state.offset.x),
        cint(state.offset.y)
      )
  
  hooks position:
    property:
      gtk_popover_set_position(state.internalWidget, toGtk(state.position))

renderable Popover of BasePopover:
  child: Widget
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_popover_new(nil.GtkWidget)
  
  hooks child:
    (build, update):
      state.updateChild(state.child, widget.valChild, gtk_popover_set_child)
  
  adder add:
    if widget.hasChild:
      raise newException(ValueError, "Unable to add multiple children to a Popover. Use a Box widget to display multiple widgets in a popover.")
    widget.hasChild = true
    widget.valChild = child

renderable PopoverMenu of BasePopover:
  ## A popover with multiple pages.
  ## It is usually used to create a menu with nested submenus.
  
  pages: Table[string, Widget]
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_popover_menu_new_from_model(nil)
  
  hooks pages:
    (build, update):
      if widget.hasPages:
        for name, page in widget.valPages:
          page.assignApp(state.app)
        
        let
          window = gtk_popover_get_child(state.internalWidget)
          viewport = gtk_widget_get_first_child(window)
          stack = gtk_widget_get_first_child(viewport)
        
        for name, page in state.pages:
          if name notin widget.valPages:
            gtk_stack_remove(stack, page.unwrapInternalWidget())
        
        for name, pageWidget in widget.valPages:
          if name in state.pages:
            let
              page = state.pages[name]
              newPage = pageWidget.update(page)
            if not newPage.isNil:
              gtk_stack_remove(stack, page.unwrapInternalWidget())
              gtk_stack_add_named(stack, newPage.unwrapInternalWidget(), name.cstring)
              state.pages[name] = newPage
          else:
            let page = pageWidget.build()
            gtk_stack_add_named(stack, page.unwrapInternalWidget(), name.cstring)
            state.pages[name] = page
  
  adder add {.name: "main".}:
    ## Adds a page to the popover menu.
    
    if name in widget.valPages:
      raise newException(ValueError, "Page \"" & name & "\" already exists")
    widget.hasPages = true
    widget.valPages[name] = child

renderable MenuButton of BaseWidget:
  child: Widget
  popover: Widget

  hooks:
    beforeBuild:
      state.internalWidget = gtk_menu_button_new()
  
  hooks child:
    (build, update):
      state.updateChild(state.child, widget.valChild, gtk_menu_button_set_child)
  
  hooks popover:
    (build, update):
      state.updateChild(state.popover, widget.valPopover, gtk_menu_button_set_popover)

  setter text: string
  setter icon: string ## Sets the icon of the MenuButton. Typically `open-menu` is used. See [recommended_tools.md](recommended_tools.md#icons) for a list of icons.
  
  adder addChild:
    if widget.hasChild:
      raise newException(ValueError, "Unable to add multiple children to a MenuButton. Use a Box widget to display multiple widgets in a MenuButton.")
    widget.hasChild = true
    widget.valChild = child
  
  adder add:
    if not widget.hasChild:
      widget.hasChild = true
      widget.valChild = child
    elif not widget.hasPopover:
      widget.hasPopover = true
      widget.valPopover = child
    else:
      raise newException(ValueError, "Unable to add more than two children to MenuButton")
  
  example:
    MenuButton {.addRight.}:
      icon = "open-menu"
      
      PopoverMenu:
        Box:
          Label(text = "My Menu")

proc `hasText=`*(menuButton: MenuButton, value: bool) = menuButton.hasChild = value
proc `valText=`*(menuButton: MenuButton, value: string) =
  menuButton.valChild = Label(hasText: true, valText: value)

proc `hasIcon=`*(menuButton: MenuButton, value: bool) = menuButton.hasChild = value
proc `valIcon=`*(menuButton: MenuButton, name: string) =
  menuButton.valChild = Icon(hasName: true, valName: name)

renderable ModelButton of BaseWidget:
  text: string
  icon: string ## The icon of the ModelButton (see [recommended_tools.md](recommended_tools.md#icons) for a list of icons)
  shortcut: string
  menuName: string
  
  proc clicked()
  
  hooks:
    beforeBuild:
      state.internalWidget = GtkWidget(g_object_new(g_type_from_name("GtkModelButton"), nil))
    connectEvents:
      state.connect(state.clicked, "clicked", eventCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.clicked)
  
  hooks text:
    property:
      var value = g_value_new(state.text)
      g_object_set_property(state.internalWidget.pointer, "text", value.addr)
      g_value_unset(value.addr)
  
  hooks icon:
    property:
      var value = g_value_new(state.icon.len > 0)
      g_object_set_property(state.internalWidget.pointer, "iconic", value.addr)
      g_value_unset(value.addr)
      if state.icon.len > 0:
        var err: GError
        let icon = g_icon_new_for_string(state.icon.cstring, err.addr)
        var value = g_value_new(icon)
        g_object_set_property(state.internalWidget.pointer, "icon", value.addr)
        g_value_unset(value.addr)
  
  hooks menuName:
    property:
      var value: GValue
      discard g_value_init(value.addr, G_TYPE_STRING)
      if state.menuName.len > 0:
        g_value_set_string(value.addr, state.menuName.cstring)
      else:
        g_value_set_string(value.addr, nil)
      g_object_set_property(state.internalWidget.pointer, "menu_name", value.addr)
      g_value_unset(value.addr)
  
  hooks shortcut:
    property:
      var value = g_value_new(state.shortcut)
      g_object_set_property(state.internalWidget.pointer, "accel", value.addr)
      g_value_unset(value.addr)
  
  example:
    PopoverMenu:
      Box:
        orient = OrientY
        
        for it in 0..<10:
          ModelButton:
            text = "Menu Entry " & $it
            
            proc clicked() =
              echo "Clicked " & $it

renderable SearchEntry of BaseWidget:
  text: string
  # child: GtkWidget # This is currently not supported
  searchDelay: uint = 100 ## Determines the minimum time after a `searchChanged` event occurred before the next can be emitted. Only available when compiling for gtk 4.8
  placeholderText: string = "Search" ## Only available when compiling for gtk 4.10
  
  proc activate() ## Triggered when the user "activated" the search e.g. by hitting "enter" key while SearchEntry is in focus.
  proc nextMatch() ## Triggered when the user hits the "next entry" keybinding while the search entry is in focus, which is Ctrl-g by default. 
  proc previousMatch() ## Triggered when the user hits the "previous entry" keybinding while the search entry is in focus, which is Ctrl-Shift-g by default.
  proc changed(searchString: string) ## Triggered when the user types in the SearchEntry.
  # proc searchStarted() # Currently not supported
  proc stopSearch() ## Triggered when the user "stops" a search, e.g. by hitting the "Esc" key while SearchEntry is in focus. 
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_search_entry_new()
    connectEvents:
      proc changedCallback(widget: GtkWidget, data: ptr EventObj[proc(searchString: string)]) =
        let searchString = $gtk_editable_get_text(widget)
        SearchEntryState(data[].widget).text = searchString
        data[].callback(searchString)
        data[].redraw()
      
      state.connect(state.activate, "activate", eventCallback)
      state.connect(state.nextMatch, "next-match", eventCallback)
      state.connect(state.previousMatch, "previous-match", eventCallback)
      state.connect(state.changed, "search-changed", changedCallback)
      # state.connect(state.searchStarted, "search-changed", eventCallback) # Currently not supported
      state.connect(state.stopSearch, "stop-search", eventCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.activate)
      state.internalWidget.disconnect(state.nextMatch)
      state.internalWidget.disconnect(state.previousMatch)
      state.internalWidget.disconnect(state.changed)
      # state.internalWidget.disconnect(state.searchStarted) # Currently not supported
      state.internalWidget.disconnect(state.stopSearch)

  # hooks child:
  #   property:
  #     gtk_search_entry_set_key_capture_widget(state.internalWidget, state.child.pointer)

  hooks text:
    property:
      gtk_editable_set_text(state.internalWidget, state.text.cstring)
    read:
      state.text = $gtk_editable_get_text(state.internalWidget)
  
  hooks searchDelay:
    property:
      when GtkMinor >= 8:
        gtk_search_entry_set_search_delay(state.internalWidget, state.searchDelay.cuint)
      else:
        discard

  hooks placeholderText:
    property:
      when GtkMinor >= 10:
        gtk_search_entry_set_placeholder_text(state.internalWidget, state.placeholderText.cstring)
      else:
        discard
    
renderable Separator of BaseWidget:
  ## A separator line.
  
  orient: Orient
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_separator_new(widget.valOrient.toGtk())

type
  UnderlineKind* = enum
    UnderlineNone, UnderlineSingle, UnderlineDouble,
    UnderlineLow, UnderlineError
  
  TagStyle* = object
    background*: Option[string]
    foreground*: Option[string]
    family*: Option[string]
    size*: Option[int]
    strikethrough*: Option[bool]
    weight*: Option[int]
    underline*: Option[UnderlineKind]
    style*: Option[CairoFontSlant]
  
  # Wrapper for the GtkTextBuffer pointer to work with destructors of nim's ARC/ORC
  # Todo: As of 16.09.2023 it is mildly buggy to try and to `TextBuffer = distinct GtkTextBuffer` and
  # have destructors act on that new type directly. It was doable as shown in Ticket #75 and Github PR #81
  # But required a =sink hook for no understandable reason *and* seemed risky due to bugs likely making it unstable.
  # The pointer wrapped by intermediate type used as ref-type via an alias approach seems more stable for now.
  # Re-evaluate this in Match 2024 to see whether we can remove the wrapper obj.
  TextBufferObj = object
    gtk: GtkTextBuffer
  
  TextBuffer* = ref TextBufferObj
  
  TextIter* = GtkTextIter
  TextTag* = GtkTextTag
  TextSlice* = HSlice[TextIter, TextIter]

crossVersionDestructor(buffer, TextBufferObj):
  if isNil(buffer.gtk):
    return
  
  g_object_unref(pointer(buffer.gtk))

proc `=copy`*(dest: var TextBufferObj, source: TextBufferObj) =
  let areSameObject = pointer(source.gtk) == pointer(dest.gtk)
  if areSameObject:
    return
  
  `=destroy`(dest)
  wasMoved(dest)
  if not isNil(source.gtk):
    g_object_ref(pointer(source.gtk))
    
  dest.gtk = source.gtk

proc newTextBuffer*(): TextBuffer =
  result = TextBuffer(gtk: gtk_text_buffer_new(nil.GtkTextTagTable))
  
{.push hint[Name]: off.}
proc g_value_new(value: UnderlineKind): GValue =
  discard g_value_init(result.addr, G_TYPE_INT)
  g_value_set_int(result.addr, cint(ord(value)))

proc g_value_new(value: CairoFontSlant): GValue =
  const IDS: array[CairoFontSlant, cint] = [
    FontSlantNormal: cint(0),
    FontSlantItalic: cint(2),
    FontSlantOblique: cint(1)
  ]
  discard g_value_init(result.addr, G_TYPE_INT)
  g_value_set_int(result.addr, IDS[value])
{.pop.}

proc registerTag*(buffer: TextBuffer, name: string, style: TagStyle): TextTag =
  result = gtk_text_buffer_create_tag(buffer.gtk, name.cstring, nil)
  for attr, value in fieldPairs(style):
    if value.isSome:
      var gvalue = g_value_new(get(value))
      g_object_set_property(result.pointer, attr.cstring, gvalue.addr)
      g_value_unset(gvalue.addr)

proc lookupTag*(buffer: TextBuffer, name: string): TextTag =
  let tab = gtk_text_buffer_get_tag_table(buffer.gtk)
  result = gtk_text_tag_table_lookup(tab, name.cstring)

proc unregisterTag*(buffer: TextBuffer, tag: TextTag) =
  let tab = gtk_text_buffer_get_tag_table(buffer.gtk)
  gtk_text_tag_table_remove(tab, tag)

proc unregisterTag*(buffer: TextBuffer, name: string) =
  buffer.unregisterTag(buffer.lookupTag(name))

{.push inline.}
proc lineCount*(buffer: TextBuffer): int =
  result = int(gtk_text_buffer_get_line_count(buffer.gtk))

proc charCount*(buffer: TextBuffer): int =
  result = int(gtk_text_buffer_get_char_count(buffer.gtk))

proc startIter*(buffer: TextBuffer): TextIter =
  gtk_text_buffer_get_start_iter(buffer.gtk, result.addr)

proc endIter*(buffer: TextBuffer): TextIter =
  gtk_text_buffer_get_end_iter(buffer.gtk, result.addr)

proc iterAtLine*(buffer: TextBuffer, line: int): TextIter =
  gtk_text_buffer_get_iter_at_line(buffer.gtk, result.addr, line.cint)

proc iterAtOffset*(buffer: TextBuffer, offset: int): TextIter =
  gtk_text_buffer_get_iter_at_offset(buffer.gtk, result.addr, offset.cint)

proc `text=`*(buffer: TextBuffer, text: string) =
  gtk_text_buffer_set_text(buffer.gtk, text.cstring, text.len.cint)

proc text*(buffer: TextBuffer, start, stop: TextIter, hiddenChars: bool = true): string =
  result = $gtk_text_buffer_get_text(
    buffer.gtk, start.unsafeAddr, stop.unsafeAddr, cbool(ord(hiddenChars))
  )

proc text*(buffer: TextBuffer, slice: TextSlice, hiddenChars: bool = true): string =
  result = buffer.text(slice.a, slice.b, hiddenChars)

proc text*(buffer: TextBuffer, hiddenChars: bool = true): string =
  result = buffer.text(buffer.startIter, buffer.endIter)

proc isModified*(buffer: TextBuffer): bool =
  result = gtk_text_buffer_get_modified(buffer.gtk) != 0

proc hasSelection*(buffer: TextBuffer): bool =
  result = gtk_text_buffer_get_has_selection(buffer.gtk) != 0

proc selection*(buffer: TextBuffer): TextSlice =
  discard gtk_text_buffer_get_selection_bounds(
    buffer.gtk, result.a.addr, result.b.addr
  )

proc placeCursor*(buffer: TextBuffer, iter: TextIter) =
  gtk_text_buffer_place_cursor(buffer.gtk, iter.unsafeAddr)

proc select*(buffer: TextBuffer, insert, other: TextIter) =
  gtk_text_buffer_select_range(buffer.gtk, insert.unsafeAddr, other.unsafeAddr)

proc delete*(buffer: TextBuffer, a, b: TextIter) =
  gtk_text_buffer_delete(buffer.gtk, a.unsafeAddr, b.unsafeAddr)

proc delete*(buffer: TextBuffer, slice: TextSlice) = buffer.delete(slice.a, slice.b)

proc insert*(buffer: TextBuffer, iter: TextIter, text: string) =
  gtk_text_buffer_insert(buffer.gtk, iter.unsafeAddr, cstring(text), cint(text.len))

proc applyTag*(buffer: TextBuffer, name: string, a, b: TextIter) =
  gtk_text_buffer_apply_tag_by_name(buffer.gtk, name.cstring, a.unsafeAddr, b.unsafeAddr)

proc applyTag*(buffer: TextBuffer, name: string, slice: TextSlice) =
  buffer.applyTag(name, slice.a, slice.b)

proc removeTag*(buffer: TextBuffer, name: string, a, b: TextIter) =
  gtk_text_buffer_remove_tag_by_name(buffer.gtk, name.cstring, a.unsafeAddr, b.unsafeAddr)

proc removeTag*(buffer: TextBuffer, name: string, slice: TextSlice) =
  buffer.removeTag(name, slice.a, slice.b)

proc removeAllTags*(buffer: TextBuffer, a, b: TextIter) =
  gtk_text_buffer_remove_all_tags(buffer.gtk, a.unsafeAddr, b.unsafeAddr)

proc removeAllTags*(buffer: TextBuffer, slice: TextSlice) =
  buffer.removeAllTags(slice.a, slice.b)

proc canRedo*(buffer: TextBuffer): bool = bool(gtk_text_buffer_get_can_redo(buffer.gtk) != 0)
proc canUndo*(buffer: TextBuffer): bool = bool(gtk_text_buffer_get_can_undo(buffer.gtk) != 0)
proc redo*(buffer: TextBuffer) = gtk_text_buffer_redo(buffer.gtk)
proc undo*(buffer: TextBuffer) = gtk_text_buffer_undo(buffer.gtk)
{.pop.}

{.push inline.}
proc `==`*(a, b: TextIter): bool =
  result = gtk_text_iter_equal(a.unsafeAddr, b.unsafeAddr) != 0

proc `<`*(a, b: TextIter): bool =
  result = gtk_text_iter_compare(a.unsafeAddr, b.unsafeAddr) < 0

proc `<=`*(a, b: TextIter): bool =
  result = gtk_text_iter_compare(a.unsafeAddr, b.unsafeAddr) <= 0

proc cmp*(a, b: TextIter): int =
  result = int(gtk_text_iter_compare(a.unsafeAddr, b.unsafeAddr))

proc contains*(slice: TextSlice, iter: TextIter): bool =
  ## Checks if `iter` is in [`slice.a`, `slice.b`)
  result = gtk_text_iter_in_range(iter.unsafeAddr, slice.a.unsafeAddr, slice.b.unsafeAddr) != 0

proc forwardChars*(iter: var TextIter, count: int): bool =
  result = gtk_text_iter_forward_to_tag_toggle(iter.addr, nil.GtkTextTag) != 0

proc forwardLine*(iter: var TextIter): bool =
  result = gtk_text_iter_forward_line(iter.addr) != 0

proc forwardToLineEnd*(iter: var TextIter): bool =
  result = gtk_text_iter_forward_to_line_end(iter.addr) != 0

proc forwardToTagToggle*(iter: var TextIter): bool =
  result = gtk_text_iter_forward_to_tag_toggle(iter.addr, nil.GtkTextTag) != 0

proc forwardToTagToggle*(iter: var TextIter, tag: TextTag): bool =
  result = gtk_text_iter_forward_to_tag_toggle(iter.addr, tag) != 0

proc backwardChars*(iter: var TextIter, count: int): bool =
  result = gtk_text_iter_backward_to_tag_toggle(iter.addr, nil.GtkTextTag) != 0

proc backwardLine*(iter: var TextIter): bool =
  result = gtk_text_iter_backward_line(iter.addr) != 0

proc backwardToTagToggle*(iter: var TextIter): bool =
  result = gtk_text_iter_backward_to_tag_toggle(iter.addr, nil.GtkTextTag) != 0

proc backwardToTagToggle*(iter: var TextIter, tag: TextTag): bool =
  result = gtk_text_iter_backward_to_tag_toggle(iter.addr, tag) != 0

proc isStart*(iter: TextIter): bool = gtk_text_iter_is_start(iter.unsafeAddr) != 0
proc isEnd*(iter: TextIter): bool = gtk_text_iter_is_end(iter.unsafeAddr) != 0
proc canInsert*(iter: TextIter): bool = gtk_text_iter_can_insert(iter.unsafeAddr) != 0

proc hasTag*(iter: TextIter, tag: TextTag): bool =
  result = gtk_text_iter_has_tag(iter.unsafeAddr, tag) != 0

proc startsTag*(iter: TextIter, tag: TextTag): bool =
  result = gtk_text_iter_starts_tag(iter.unsafeAddr, tag) != 0

proc endsTag*(iter: TextIter, tag: TextTag): bool =
  result = gtk_text_iter_ends_tag(iter.unsafeAddr, tag) != 0

proc offset*(iter: TextIter): int = gtk_text_iter_get_offset(iter.unsafeAddr)
proc line*(iter: TextIter): int = gtk_text_iter_get_line(iter.unsafeAddr)
proc lineOffset*(iter: TextIter): int = gtk_text_iter_get_line_offset(iter.unsafeAddr)
proc `offset=`*(iter: TextIter, val: int) = gtk_text_iter_set_offset(iter.unsafeAddr, cint(val))
proc `line=`*(iter: TextIter, val: int) = gtk_text_iter_set_line(iter.unsafeAddr, cint(val))
proc `lineOffset=`*(iter: TextIter, val: int) = gtk_text_iter_set_line_offset(iter.unsafeAddr, cint(val))
{.pop.}

renderable TextView of BaseWidget:
  ## A text editor with support for formatted text.
  
  buffer: TextBuffer ## The buffer containing the displayed text.
  monospace: bool = false
  cursorVisible: bool = true
  editable: bool = true
  acceptsTab: bool = true
  indent: int = 0
  
  proc changed()
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_text_view_new()
    connectEvents:
      if not state.changed.isNil:
        state.changed.handler = g_signal_connect(
          GtkWidget(state.buffer.gtk), "changed", eventCallback, state.changed[].addr
        )
    disconnectEvents:
      GtkWidget(state.buffer.gtk).disconnect(state.changed)
  
  hooks monospace:
    property:
      gtk_text_view_set_monospace(state.internalWidget, cbool(ord(state.monospace)))
  
  hooks cursorVisible:
    property:
      gtk_text_view_set_cursor_visible(state.internalWidget, cbool(ord(state.cursorVisible)))
  
  hooks editable:
    property:
      gtk_text_view_set_editable(state.internalWidget, cbool(ord(state.editable)))
  
  hooks acceptsTab:
    property:
      gtk_text_view_set_accepts_tab(state.internalWidget, cbool(ord(state.acceptsTab)))
  
  hooks indent:
    property:
      gtk_text_view_set_indent(state.internalWidget, cint(state.indent))
  
  hooks buffer:
    property:
      if state.buffer.isNil:
        raise newException(ValueError, "TextView.buffer must not be nil")
      gtk_text_view_set_buffer(state.internalWidget, state.buffer.gtk)

renderable ListBoxRow of BaseWidget:
  ## A row in a `ListBox`.
  
  child: Widget
  
  proc activate()
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_list_box_row_new()
    connectEvents:
      state.connect(state.activate, "activate", eventCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.activate)
  
  hooks child:
    (build, update):
      state.updateChild(state.child, widget.valChild, gtk_list_box_row_set_child)
  
  adder add:
    if widget.hasChild:
      raise newException(ValueError, "Unable to add multiple children to a ListBoxRow. Use a Box widget to display multiple widgets in a ListBoxRow.")
    widget.hasChild = true
    widget.valChild = child

  
  example:
    ListBox:
      for it in 0..<10:
        ListBoxRow {.addRow.}:
          proc activate() =
            echo it
          Label(text = $it)

const ListBoxNavigationSidebar* = "navigation-sidebar".StyleClass

type SelectionMode* = enum
  SelectionNone, SelectionSingle, SelectionBrowse, SelectionMultiple

renderable ListBox of BaseWidget:
  rows: seq[Widget]
  selectionMode: SelectionMode
  selected: HashSet[int] ## Indices of the currently selected items.

  proc select(rows: HashSet[int])
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_list_box_new()
      
      proc handleUnrealize(widget: GtkWidget, data: ptr ListBoxState) {.cdecl.} =
        let state = unwrapSharedCell(data)
        state.internalWidget.disconnect(state.select)
      
      let data = allocSharedCell(state)
      discard g_signal_connect(state.internalWidget, "unrealize", handleUnrealize, data)
    connectEvents:
      proc selectedRowsChanged(widget: GtkWidget, data: ptr EventObj[proc (state: HashSet[int])]) {.cdecl.} =
        let selected = gtk_list_box_get_selected_rows(widget)
        var
          rows = initHashSet[int]()
          cur = selected
        while not cur.isNil:
          rows.incl(int(gtk_list_box_row_get_index(GtkWidget(cur[].data))))
          cur = cur[].next
        g_list_free(selected)
        ListBoxState(data[].widget).selected = rows
        data[].callback(rows)
        data[].redraw()
      
      state.connect(state.select, "selected-rows-changed", selectedRowsChanged)
    disconnectEvents:
      state.internalWidget.disconnect(state.select)
  
  hooks rows:
    (build, update):
      state.updateChildren(
        state.rows,
        widget.valRows,
        gtk_list_box_append,
        gtk_list_box_insert,
        gtk_list_box_remove
      )
  
  hooks selectionMode:
    property:
      gtk_list_box_set_selection_mode(state.internalWidget,
        GtkSelectionMode(ord(state.selectionMode))
      )
  
  hooks selected:
    (build, update):
      if widget.hasSelected:
        for index in state.selected - widget.valSelected:
          if index >= state.rows.len:
            continue
          let row = state.rows[index].unwrapInternalWidget()
          gtk_list_box_unselect_row(state.internalWidget, row)
        for index in widget.valSelected - state.selected:
          let row = state.rows[index].unwrapInternalWidget()
          gtk_list_box_select_row(state.internalWidget, row)
        state.selected = widget.valSelected
        for row in state.selected:
          if row >= state.rows.len:
            raise newException(IndexDefect, "Unable to select row " & $row & ", since there are only " & $state.rows.len & " rows in the ListBox.")

  adder addRow:
    ## Adds a row to the list. The added child widget must be a `ListBoxRow`.
    widget.hasRows = true
    widget.valRows.add(child)
  
  adder add:
    if child of ListBoxRow:
      widget.addRow(ListBoxRow(child))
    else:
      widget.addRow(ListBoxRow(hasChild: true, valChild: child))
  
  example:
    ListBox:
      for it in 0..<10:
        Label(text = $it)

renderable FlowBoxChild of BaseWidget:
  child: Widget
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_flow_box_child_new()
  
  hooks child:
    (build, update):
      state.updateChild(state.child, widget.valChild, gtk_flow_box_child_set_child)
  
  adder add:
    if widget.hasChild:
      raise newException(ValueError, "Unable to add multiple children to a FlowBoxChild. Use a Box widget to display multiple widgets in a FlowBoxChild.")
    widget.hasChild = true
    widget.valChild = child
  
  example:
    FlowBox:
      columns = 1..5
      for it in 0..<10:
        FlowBoxChild {.addChild.}:
          Label(text = $it)

renderable FlowBox of BaseWidget:
  homogeneous: bool
  rowSpacing: int
  columnSpacing: int
  columns: HSlice[int, int] = 1..5
  selectionMode: SelectionMode
  children: seq[Widget]
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_flow_box_new()
  
  hooks homogeneous:
    property:
      gtk_flow_box_set_homogeneous(state.internalWidget, cbool(ord(state.homogeneous)))
  
  hooks rowSpacing:
    property:
      gtk_flow_box_set_row_spacing(state.internalWidget, cuint(state.rowSpacing))
  
  hooks columnSpacing:
    property:
      gtk_flow_box_set_column_spacing(state.internalWidget, cuint(state.columnSpacing))
  
  hooks columns:
    property:
      gtk_flow_box_set_min_children_per_line(state.internalWidget, cuint(state.columns.a))
      gtk_flow_box_set_max_children_per_line(state.internalWidget, cuint(state.columns.b))
  
  hooks selectionMode:
    property:
      gtk_flow_box_set_selection_mode(state.internalWidget,
        GtkSelectionMode(ord(state.selectionMode))
      )
  
  hooks children:
    (build, update):
      state.updateChildren(
        state.children,
        widget.valChildren,
        gtk_flow_box_append,
        gtk_flow_box_insert,
        gtk_flow_box_remove
      )
  
  adder addChild:
    widget.hasChildren = true
    widget.valChildren.add(child)

  adder add:
    widget.addChild(FlowBoxChild(hasChild: true, valChild: child))
  
  example:
    FlowBox:
      columns = 1..5
      for it in 0..<10:
        Label(text = $it)

renderable Frame of BaseWidget:
  label: string
  align: tuple[x, y: float] = (0.0, 0.0)
  child: Widget
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_frame_new(nil)
  
  hooks label:
    property:
      if state.label.len == 0:
        gtk_frame_set_label(state.internalWidget, nil)
      else:
        gtk_frame_set_label(state.internalWidget, state.label.cstring)
  
  hooks align:
    property:
      gtk_frame_set_label_align(state.internalWidget,
        state.align.x.cfloat, state.align.y.cfloat
      )
  
  hooks child:
    (build, update):
      state.updateChild(state.child, widget.valChild, gtk_frame_set_child)
  
  adder add:
    if widget.hasChild:
      raise newException(ValueError, "Unable to add multiple children to a Frame. Use a Box widget to display multiple widgets in a Frame.")
    widget.hasChild = true
    widget.valChild = child 
  
  example:
    Frame:
      label = "Frame Title"
      align = (0.2, 0.0)
      Label:
        text = "Content"

renderable DropDown of BaseWidget:
  ## A drop down that allows the user to select an item from a list of items.
  
  items: seq[string]
  selected: int ## Index of the currently selected item.
  enableSearch: bool
  showArrow: bool = true
  
  proc select(item: int)
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_drop_down_new(GListModel(nil), nil)
      
      proc getString(stringObject: GtkStringObject): pointer {.cdecl.} =
        let str = gtk_string_object_get_string(stringObject)
        result = g_strdup(str)
      
      let expr = gtk_cclosure_expression_new(G_TYPE_STRING, nil, 0, nil, GCallback(getString), nil, nil)
      gtk_drop_down_set_expression(state.internalWidget, expr)
      gtk_expression_unref(expr)
    connectEvents:
      proc selectCallback(widget: GtkWidget,
                          pspec: pointer,
                          data: ptr EventObj[proc (item: int)]) {.cdecl.} =
        let
          selected = int(gtk_drop_down_get_selected(widget))
          state = DropDownState(data[].widget)
        if selected != state.selected:
          state.selected = selected
          data[].callback(selected)
          data[].redraw()
      
      state.connect(state.select, "notify::selected", selectCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.select)
  
  hooks enableSearch:
    property:
      gtk_drop_down_set_enable_search(state.internalWidget, cbool(ord(state.enableSearch)))
  
  hooks items:
    property:
      let items = allocCStringArray(state.items)
      defer: deallocCStringArray(items)
      gtk_drop_down_set_model(state.internalWidget, gtk_string_list_new(items))
  
  hooks selected:
    property:
      gtk_drop_down_set_selected(state.internalWidget, cuint(state.selected))
  
  hooks showArrow:
    property:
      gtk_drop_down_set_show_arrow(state.internalWidget, cbool(ord(state.showArrow)))
  
  example:
    DropDown:
      items = @["Option 1", "Option 2", "Option 3"]
      selected = app.selectedItem
      
      proc select(itemIndex: int) =
        app.selectedItem = itemIndex

type
  GridRegion = object
    x, y: int
    width, height: int
  
  GridChild[T] = object
    widget: T
    region: GridRegion
    hExpand: bool
    vExpand: bool
    hAlign: Align
    vAlign: Align

proc assignApp(child: GridChild[Widget], app: Viewable) =
  child.widget.assignApp(app)

proc attach(grid: GtkWidget, child: GridChild[WidgetState]) =
  gtk_grid_attach(grid,
    child.widget.unwrapInternalWidget(),
    child.region.x.cint,
    child.region.y.cint,
    child.region.width.cint,
    child.region.height.cint
  )

renderable Grid of BaseWidget:
  ## A grid layout.
  
  children: seq[GridChild[Widget]]
  rowSpacing: int ## Spacing between the rows of the grid.
  columnSpacing: int ## Spacing between the columns of the grid.
  rowHomogeneous: bool
  columnHomogeneous: bool
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_grid_new()
  
  hooks rowSpacing:
    property:
      gtk_grid_set_row_spacing(state.internalWidget, state.rowSpacing.cuint)
  
  hooks columnSpacing:
    property:
      gtk_grid_set_column_spacing(state.internalWidget, state.columnSpacing.cuint)
  
  hooks rowHomogeneous:
    property:
      gtk_grid_set_row_homogeneous(state.internalWidget, cbool(ord(state.rowHomogeneous)))
  
  hooks columnHomogeneous:
    property:
      gtk_grid_set_column_homogeneous(state.internalWidget, cbool(ord(state.columnHomogeneous)))
  
  hooks children:
    (build, update):
      widget.valChildren.assignApp(state.app)
      var it = 0
      while it < widget.valChildren.len and it < state.children.len:
        let
          oldChild = state.children[it].widget
          newChild = widget.valChildren[it].widget.update(oldChild)
        
        var readd = false
        if not newChild.isNil:
          state.children[it].widget = newChild
          readd = true
        
        if widget.valChildren[it].region != state.children[it].region:
          state.children[it].region = widget.valChildren[it].region
          readd = true
        
        if readd:
          let widget = oldChild.unwrapInternalWidget()
          g_object_ref(pointer(widget))
          gtk_grid_remove(state.internalWidget, widget)
          state.internalWidget.attach(state.children[it])
          g_object_unref(pointer(widget))
        
        let childWidget = state.children[it].widget.unwrapInternalWidget()
        
        if readd or state.children[it].hExpand != widget.valChildren[it].hExpand:
          state.children[it].hExpand = widget.valChildren[it].hExpand
          gtk_widget_set_hexpand(childWidget, cbool(ord(state.children[it].hExpand)))
        
        if readd or state.children[it].vExpand != widget.valChildren[it].vExpand:
          state.children[it].vExpand = widget.valChildren[it].vExpand
          gtk_widget_set_vexpand(childWidget, cbool(ord(state.children[it].vExpand)))
        
        if readd or state.children[it].hAlign != widget.valChildren[it].hAlign:
          state.children[it].hAlign = widget.valChildren[it].hAlign
          gtk_widget_set_halign(childWidget, toGtk(state.children[it].hAlign))
        
        if readd or state.children[it].vAlign != widget.valChildren[it].vAlign:
          state.children[it].vAlign = widget.valChildren[it].vAlign
          gtk_widget_set_valign(childWidget, toGtk(state.children[it].vAlign))
        
        it += 1
      
      while it < widget.valChildren.len:
        let
          updater = widget.valChildren[it]
          child = GridChild[WidgetState](
            widget: updater.widget.build(),
            region: updater.region,
            hExpand: updater.hExpand,
            vExpand: updater.vExpand,
            hAlign: updater.hAlign,
            vAlign: updater.vAlign
          )
        
        state.internalWidget.attach(child)
        
        let childWidget = child.widget.unwrapInternalWidget()
        gtk_widget_set_hexpand(childWidget, cbool(ord(child.hExpand)))
        gtk_widget_set_vexpand(childWidget, cbool(ord(child.vExpand)))
        gtk_widget_set_halign(childWidget, toGtk(child.hAlign))
        gtk_widget_set_valign(childWidget, toGtk(child.vAlign))
        
        state.children.add(child)
        
        it += 1
      
      while it < state.children.len:
        let child = state.children.pop()
        gtk_grid_remove(state.internalWidget, child.widget.unwrapInternalWidget())
        it += 1
  
  adder add {.x: 0, y: 0, width: 1, height: 1,
              hExpand: false, vExpand: false,
              hAlign: AlignFill, vAlign: AlignFill.}:
    ## Adds a child at the given location to the grid.
    ## The location of the child within the grid can be set using the `x`, `y`, `width` and `height` properties.
    ## The `hAlign` and `vAlign` properties allow you to set the horizontal and vertical 
    ## alignment of the child within its allocated area. They may be one of `AlignFill`,
    ## `AlignStart`, `AlignEnd` or `AlignCenter`.
    
    widget.hasChildren = true
    widget.valChildren.add(GridChild[Widget](
      widget: child,
      region: GridRegion(
        x: x,
        y: y,
        width: width,
        height: height
      ),
      hExpand: hExpand,
      vExpand: vExpand,
      hAlign: hAlign,
      vAlign: vAlign
    ))
  
  setter spacing: int ## Sets the spacing between the rows and columns of the grid.
  setter homogeneous: bool
  
  example:
    Grid:
      spacing = 6
      margin = 12
      
      Button {.x: 1, y: 1, hExpand: true, vExpand: true.}:
        text = "A"
      
      Button {.x: 2, y: 1.}:
        text = "B"
      
      Button {.x: 1, y: 2, width: 2, hAlign: AlignCenter.}:
        text = "C"

proc `hasSpacing=`*(grid: Grid, has: bool) =
  grid.hasColumnSpacing = has
  grid.hasRowSpacing = has

proc `valSpacing=`*(grid: Grid, spacing: int) =
  grid.valRowSpacing = spacing
  grid.valColumnSpacing = spacing

proc `hasHomogeneous=`*(grid: Grid, has: bool) =
  grid.hasColumnHomogeneous = has
  grid.hasRowHomogeneous = has

proc `valHomogeneous=`*(grid: Grid, homogeneous: bool) =
  grid.valRowHomogeneous = homogeneous
  grid.valColumnHomogeneous = homogeneous

type FixedChild[T] = object
  widget: T
  x, y: float

proc assignApp(child: FixedChild[Widget], app: Viewable) =
  child.widget.assignApp(app)

renderable Fixed of BaseWidget:
  ## A layout where children are placed at fixed positions.
  
  children: seq[FixedChild[Widget]]
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_fixed_new()
  
  hooks children:
    (build, update):
      widget.valChildren.assignApp(state.app)
      
      var
        it = 0
        forceReadd = false
      while it < widget.valChildren.len and it < state.children.len:
        let updater = widget.valChildren[it]
        var fixedChild = state.children[it]
        
        let newChild = updater.widget.update(fixedChild.widget)
        
        if not newChild.isNil or forceReadd:
          let oldChild = fixedChild.widget.unwrapInternalWidget()
          g_object_ref(pointer(oldChild))
          gtk_fixed_remove(state.internalWidget, oldChild)
          if not newChild.isNil:
            fixedChild.widget = newChild
          gtk_fixed_put(
            state.internalWidget,
            fixedChild.widget.unwrapInternalWidget(),
            cdouble(fixedChild.x),
            cdouble(fixedChild.y)
          )
          g_object_unref(pointer(oldChild))
          forceReadd = true
        elif updater.x != fixedChild.x or updater.y != fixedChild.y:
          fixedChild.x = updater.x
          fixedChild.y = updater.y
          gtk_fixed_move(
            state.internalWidget,
            fixedChild.widget.unwrapInternalWidget(),
            cdouble(fixedChild.x),
            cdouble(fixedChild.y)
          )
        
        state.children[it] = fixedChild
        it += 1
      
      while it < widget.valChildren.len:
        let
          updater = widget.valChildren[it]
          fixedChild = FixedChild[WidgetState](
            widget: updater.widget.build(),
            x: updater.x,
            y: updater.y
          )
        
        gtk_fixed_put(
          state.internalWidget,
          fixedChild.widget.unwrapInternalWidget(),
          cdouble(fixedChild.x),
          cdouble(fixedChild.y)
        )
        
        state.children.add(fixedChild)
        it += 1
      
      while it < state.children.len:
        let fixedChild = state.children.pop()
        gtk_fixed_remove(state.internalWidget, fixedChild.widget.unwrapInternalWidget())
  
  adder add {.x: 0.0, y: 0.0.}:
    ## Adds a child at the given position
    widget.hasChildren = true
    widget.valChildren.add(FixedChild[Widget](
      widget: child, x: x, y: y
    ))
  
  example:
    Fixed:
      Label(text = "Fixed Layout") {.x: 200, y: 100.}

renderable ContextMenu:
  ## Adds a context menu to a widget.
  ## Context menus are shown when the user right clicks the widget.
  
  child: Widget
  menu: Widget
  controller: GtkEventController = GtkEventController(nil)
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)
  
  hooks controller:
    (build, update):
      discard
  
  hooks child:
    (build, update):
      proc addChild(box, child: GtkWidget) {.cdecl.} =
        gtk_widget_set_hexpand(child, 1)
        gtk_box_append(box, child)
      
      state.updateChild(state.child, widget.valChild, addChild, gtk_box_remove)
  
  hooks menu:
    (build, update):
      proc replace(box, oldMenu, newMenu: GtkWidget) {.locker.} =
        if not oldMenu.isNil:
          gtk_widget_remove_controller(box, state.controller)
          state.controller = GtkEventController(nil)
          gtk_box_remove(box, oldMenu)
        assert state.controller.isNil
        
        if not newMenu.isNil:
          const RIGHT_CLICK = cuint(3)
          let cont = gtk_gesture_click_new()
          gtk_gesture_single_set_button(cont, RIGHT_CLICK)
          
          proc pressed(gesture: GtkEventController,
                       n_press: cint,
                       x, y: cdouble,
                       data: pointer) =
            let popover = GtkWidget(data)
            gtk_popover_present(popover)
            var rect = GdkRectangle(x: cint(x), y: cint(y), width: 1, height: 1)
            gtk_popover_set_pointing_to(popover, rect.addr)
            gtk_popover_popup(popover)
          
          discard g_signal_connect(cont, "pressed", pressed, pointer(newMenu))
          
          gtk_widget_add_controller(box, cont)
          state.controller = cont
          
          gtk_widget_set_halign(newMenu, GTK_ALIGN_START)
          gtk_box_append(box, newMenu)
      
      state.updateChild(state.menu, widget.valMenu, replace)
  
  adder add:
    if widget.hasChild:
      raise newException(ValueError, "Unable to add multiple children to a ContextMenu.")
    widget.hasChild = true
    widget.valChild = child
  
  adder addMenu:
    if widget.hasMenu:
      raise newException(ValueError, "Unable to add multiple menus to a ContextMenu.")
    widget.hasMenu = true
    widget.valMenu = child
  
  example:
    ContextMenu:
      Label:
        text = "Right click here"
      
      PopoverMenu {.addMenu.}:
        hasArrow = false
        
        Box(orient = OrientY):
          for it in 0..<3:
            ModelButton:
              text = "Menu Entry " & $it

type LevelBarMode* = enum
  LevelBarContinuous
  LevelBarDiscrete

proc toGtk(mode: LevelBarMode): GtkLevelBarMode =
  result = GtkLevelBarMode(ord(mode))

renderable LevelBar of BaseWidget:
  value: float = 0.0
  min: float = 0.0
  max: float = 1.0
  inverted: bool = false
  mode: LevelBarMode = LevelBarContinuous
  orient: Orient = OrientX
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_level_bar_new()
  
  hooks value:
    property:
      gtk_level_bar_set_value(state.internalWidget, cdouble(state.value))
  
  hooks min:
    property:
      gtk_level_bar_set_min_value(state.internalWidget, cdouble(state.min))
  
  hooks max:
    property:
      gtk_level_bar_set_max_value(state.internalWidget, cdouble(state.max))
  
  hooks inverted:
    property:
      gtk_level_bar_set_inverted(state.internalWidget, cbool(ord(state.inverted)))
  
  hooks mode:
    property:
      gtk_level_bar_set_mode(state.internalWidget, toGtk(state.mode))
  
  hooks orient:
    property:
      gtk_orientable_set_orientation(state.internalWidget, toGtk(state.orient))
  
  example:
    LevelBar:
      value = 0.2
      min = 0
      max = 1
  
  example:
    LevelBar:
      value = 2
      max = 10
      orient = OrientY
      mode = LevelBarDiscrete

renderable Calendar of BaseWidget:
  ## Displays a calendar
  
  date: DateTime
  markedDays: seq[int] = @[]
  showDayNames: bool = true
  showHeading: bool = true
  showWeekNumbers: bool = true
  
  proc daySelected(date: DateTime)
  proc nextMonth(date: DateTime)
  proc prevMonth(date: DateTime)
  proc nextYear(date: DateTime)
  proc prevYear(date: DateTime)
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_calendar_new()
    connectEvents:
      proc selectedCallback(widget: GtkWidget, data: ptr EventObj[proc (state: DateTime)]) {.cdecl.} =
        let
          gtkDate = gtk_calendar_get_date(widget)
          date = fromUnix(g_date_time_to_unix(gtkDate)).inZone(utc())
        g_date_time_unref(gtkDate)
        
        CalendarState(data[].widget).date = date
        data[].callback(date)
        data[].redraw()
      
      state.connect(state.daySelected, "day-selected", selectedCallback)
      state.connect(state.nextMonth, "next-month", selectedCallback)
      state.connect(state.prevMonth, "prev-month", selectedCallback)
      state.connect(state.nextYear, "next-year", selectedCallback)
      state.connect(state.prevYear, "prev-year", selectedCallback)
    disconnectEvents:
      state.internalWidget.disconnect(state.daySelected)
      state.internalWidget.disconnect(state.nextMonth)
      state.internalWidget.disconnect(state.prevMonth)
      state.internalWidget.disconnect(state.nextYear)
      state.internalWidget.disconnect(state.prevYear)
  
  hooks date:
    property:
      let
        unix = state.date.toTime().toUnix()
        dateTime = g_date_time_new_from_unix_local(unix)
      gtk_calendar_select_day(state.internalWidget, dateTime)
      g_date_time_unref(dateTime)
  
  hooks markedDays:
    property:
      gtk_calendar_clear_marks(state.internalWidget)
      for day in state.markedDays:
        gtk_calendar_mark_day(state.internalWidget, cuint(day))
  
  hooks showDayNames:
    property:
      gtk_calendar_set_show_day_names(state.internalWidget, cbool(ord(state.showDayNames)))
  
  hooks showHeading:
    property:
      gtk_calendar_set_show_heading(state.internalWidget, cbool(ord(state.showHeading)))
  
  hooks showWeekNumbers:
    property:
      gtk_calendar_set_show_week_numbers(state.internalWidget, cbool(ord(state.showWeekNumbers)))
  
  example:
    Calendar:
      date = app.date
      
      proc select(date: DateTime) =
        ## Shortcut for handling all calendar events (daySelected,
        ## nextMonth, prevMonth, nextYear, prevYear)
        app.date = date

proc `select=`*(calendar: Calendar, event: Event[proc(date: DateTime)]) =
  if not event.isNil:
    calendar.daySelected = Event[proc(date: DateTime)](callback: event.callback)
    calendar.nextMonth = Event[proc(date: DateTime)](callback: event.callback)
    calendar.prevMonth = Event[proc(date: DateTime)](callback: event.callback)
    calendar.nextYear = Event[proc(date: DateTime)](callback: event.callback)
    calendar.prevYear = Event[proc(date: DateTime)](callback: event.callback)

type
  DialogResponseKind* = enum
    DialogCustom,
    DialogReject, DialogAccept, DialogCancel,
    DialogDeleteEvent, DialogOk, DialogClose
  
  DialogResponse* = object
    case kind*: DialogResponseKind:
      of DialogCustom: id*: int
      else: discard

proc toDialogResponse*(id: cint): DialogResponse =
  case id:
    of -2: result = DialogResponse(kind: DialogReject)
    of -3: result = DialogResponse(kind: DialogAccept)
    of -4: result = DialogResponse(kind: DialogDeleteEvent)
    of -5: result = DialogResponse(kind: DialogOk)
    of -6: result = DialogResponse(kind: DialogCancel)
    of -7: result = DialogResponse(kind: DialogClose)
    else: result = DialogResponse(kind: DialogCustom, id: int(id))

proc toGtk*(resp: DialogResponse): cint =
  case resp.kind:
    of DialogCustom: result = resp.id.cint
    of DialogReject: result = -2
    of DialogAccept: result = -3
    of DialogDeleteEvent: result = -4
    of DialogOk: result = -5
    of DialogCancel: result = -6
    of DialogClose: result = -7

renderable DialogButton:
  ## A button which closes the currently open dialog and sends a response to the caller.
  ## This widget can only be used with the `addButton` adder of `Dialog` or `BuiltinDialog`.
  
  text: string
  response: DialogResponse
  privateStyle {.private.}: HashSet[StyleClass]
  
  setter res: DialogResponseKind
  setter style: varargs[StyleClass] ## Applies CSS classes to the button. There are some pre-defined classes available: `ButtonSuggested`, `ButtonDestructive`, `ButtonFlat`, `ButtonPill` or `ButtonCircular`. You can also use custom CSS classes using `StyleClass("my-class")`. Consult the [GTK4 documentation](https://developer.gnome.org/hig/patterns/controls/buttons.html?highlight=button#button-styles) for guidance on what to use.
  setter style: HashSet[StyleClass] ## Applies CSS classes to the button.
  setter style: StyleClass  ## Applies CSS classes to the button.
  
  hooks privateStyle:
    (build, update):
      updateStyle(state, widget)

proc `hasStyle=`*(button: DialogButton, has: bool) =
  button.hasPrivateStyle = has

proc `valStyle=`*(button: DialogButton, cssClasses: HashSet[StyleClass]) =
  button.valPrivateStyle = cssClasses

proc `valStyle=`*(button: DialogButton, cssClasses: varargs[StyleClass]) =
  button.valPrivateStyle = cssClasses.toHashSet()

proc `valStyle=`*(button: DialogButton, cssClass: StyleClass) =
  button.valPrivateStyle = [cssClass].toHashSet()

proc `hasRes=`*(button: DialogButton, value: bool) =
  button.hasResponse = value

proc `valRes=`*(button: DialogButton, kind: DialogResponseKind) =
  button.valResponse = DialogResponse(kind: kind)

renderable Dialog of Window:
  ## A window which can contain `DialogButton` widgets in its header bar.

  buttons: seq[DialogButton]
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_dialog_new_with_buttons("", nil.GtkWidget, GTK_DIALOG_USE_HEADER_BAR, nil)
      gtk_window_set_child(state.internalWidget, nil.GtkWidget)
  
  hooks buttons:
    build:
      for button in widget.val_buttons:
        let
          buttonWidget = gtk_dialog_add_button(state.internalWidget,
            button.valText.cstring,
            button.valResponse.toGtk
          )
          ctx = gtk_widget_get_style_context(buttonWidget)
        for styleClass in button.valPrivateStyle:
          gtk_style_context_add_class(ctx, cstring($styleClass))
  
  adder addButton
  
  example:
    Dialog:
      title = "My Dialog"
      defaultSize = (300, 200)
      
      DialogButton {.addButton.}:
        text = "Ok"
        res = DialogAccept
      
      DialogButton {.addButton.}:
        text = "Cancel"
        res = DialogCancel
      
      Label(text = "Hello, world!")

proc addButton*(dialog: Dialog, button: DialogButton) =
  dialog.hasButtons = true
  dialog.valButtons.add(button)

renderable BuiltinDialog of BaseWidget:
  ## Base widget for builtin dialogs.
  ## If you want to create a custom dialog, you should use `Window` or `Dialog` instead.
  
  title: string
  buttons: seq[DialogButton]
  
  hooks buttons:
    build:
      for button in widget.valButtons:
        let
          buttonWidget = gtk_dialog_add_button(state.internalWidget,
            button.valText.cstring,
            button.valResponse.toGtk
          )
          ctx = gtk_widget_get_style_context(buttonWidget)
        for styleClass in button.valPrivateStyle:
          gtk_style_context_add_class(ctx, cstring($styleClass))
  
  adder addButton

proc open*(app: Viewable, widget: Widget): tuple[res: DialogResponse, state: WidgetState] =
  let
    state = widget.build()
    dialogState = state.unwrapRenderable()
    window = app.unwrapInternalWidget()
    dialog = state.unwrapInternalWidget()
  gtk_window_set_transient_for(dialog, window)
  gtk_window_set_modal(dialog, cbool(bool(true)))
  gtk_window_present(dialog)
  
  proc destroyDialog(dialog: GtkWidget, closed: ptr bool) {.cdecl.} =
    closed[] = true
  
  var closed = false
  discard g_signal_connect(dialog, "destroy", destroyDialog , closed.addr)
  
  if dialogState of DialogState or dialogState of BuiltinDialogState:
    proc response(dialog: GtkWidget, responseId: cint, res: ptr cint) {.cdecl.} =
      res[] = responseId
    
    var res = low(cint)
    discard g_signal_connect(dialog, "response", response, res.addr)
    while res == low(cint):
      discard g_main_context_iteration(nil.GMainContext, cbool(ord(true)))
    
    state.read()
    if not closed:
      gtk_window_destroy(dialog)
    result = (toDialogResponse(res), state)
  else:
    while not closed:
      discard g_main_context_iteration(nil.GMainContext, cbool(ord(true)))
    
    state.read()
    result = (DialogResponse(), state)


proc addButton*(dialog: BuiltinDialog, button: DialogButton) =
  dialog.hasButtons = true
  dialog.valButtons.add(button)

type FileChooserAction* = enum
  FileChooserOpen,
  FileChooserSave,
  FileChooserSelectFolder,
  FileChooserCreateFolder

renderable FileChooserDialog of BuiltinDialog:
  ## A dialog for opening/saving files or folders.
  
  action: FileChooserAction
  selectMultiple: bool = false
  initialPath: string ## Path of the initially shown folder
  filenames: seq[string] ## The selected file paths
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_file_chooser_dialog_new(
        widget.valTitle.cstring,
        nil.GtkWidget,
        GtkFileChooserAction(ord(widget.valAction)),
        nil
      )
  
  hooks selectMultiple:
    property:
      gtk_file_chooser_set_select_multiple(state.internalWidget,
        cbool(ord(state.selectMultiple))
      )
  
  hooks initialPath:
    build:
      if widget.hasInitialPath:
        state.initialPath = widget.valInitialPath
      if state.initialPath.len > 0:
        let
          file = g_file_new_for_path(state.initialPath.cstring)
          success = gtk_file_chooser_set_current_folder(state.internalWidget, file, nil)
        if success == cbool(0):
          raise newException(IOError, "Failed to set initialPath of FileChooserDialog")
        g_object_unref(pointer(file))
  
  hooks filenames:
    read:
      state.filenames = @[]
      let files = gtk_file_chooser_get_files(state.internalWidget)
      for file in files:
        state.filenames.add($g_file_get_path(GFile(file)))
        g_object_unref(file)
      g_object_unref(pointer(files))
  
  example:
    FileChooserDialog:
      title = "Open a File"
      action = FileChooserOpen
      selectMultiple = true
      
      DialogButton {.addButton.}:
        text = "Cancel"
        res = DialogCancel
      
      DialogButton {.addButton.}:
        text = "Open"
        res = DialogAccept
        style = [ButtonSuggested]

proc filename*(dialog: FileChooserDialogState): string {.deprecated: "Use filenames instead".} =
  case dialog.filenames.len:
    of 0: result = ""
    of 1: result = dialog.filenames[0]
    else:
      raise newException(ValueError, "Multiple files were selected")

renderable ColorChooserDialog of BuiltinDialog:
  ## A dialog for choosing a color.
  
  color: tuple[r, g, b, a: float] = (0.0, 0.0, 0.0, 1.0)
  useAlpha: bool = false
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_color_chooser_dialog_new(
        widget.valTitle.cstring,
        nil.GtkWidget
      )
  
  hooks color:
    property:
      var rgba = GdkRgba(
        r: cdouble(state.color.r),
        g: cdouble(state.color.g),
        b: cdouble(state.color.b),
        a: cdouble(state.color.a)
      )
      gtk_color_chooser_set_rgba(state.internalWidget, rgba.addr)
    read:
      var color: GdkRgba
      gtk_color_chooser_get_rgba(state.internalWidget, color.addr)
      state.color = (color.r.float, color.g.float, color.b.float, color.a.float)
  
  hooks useAlpha:
    property:
      gtk_color_chooser_set_use_alpha(state.internalWidget, cbool(ord(state.useAlpha)))

  example:
    ColorChooserDialog:
      color = (1.0, 0.0, 0.0, 1.0)
      useAlpha = true

renderable MessageDialog of BuiltinDialog:
  ## A dialog for showing a message to the user.
  
  message: string
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_message_dialog_new(
        nil.GtkWidget,
        GTK_DIALOG_DESTROY_WITH_PARENT,
        GTK_MESSAGE_INFO,
        GTK_BUTTONS_NONE,
        widget.valMessage.cstring,
        nil
      )
  
  example:
    MessageDialog:
      message = "Hello, world!"
      
      DialogButton {.addButton.}:
        text = "Ok"
        res = DialogAccept

renderable AboutDialog of BaseWidget:
  programName: string
  logo: string
  copyright: string
  version: string
  license: string
  credits: seq[(string, seq[string])]
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_about_dialog_new()
  
  hooks programName:
    property:
      gtk_about_dialog_set_program_name(state.internalWidget, state.programName.cstring)
  
  hooks logo:
    property:
      gtk_about_dialog_set_logo_icon_name(state.internalWidget, state.logo.cstring)
  
  hooks copyright:
    property:
      gtk_about_dialog_set_copyright(state.internalWidget, state.copyright.cstring)
  
  hooks version:
    property:
      gtk_about_dialog_set_version(state.internalWidget, state.version.cstring)
  
  hooks license:
    property:
      gtk_about_dialog_set_license(state.internalWidget, state.license.cstring)
  
  hooks credits:
    build:
      if widget.hasCredits:
        state.credits = widget.valCredits
        for (sectionName, people) in state.credits:
          let names = allocCStringArray(people)
          defer: deallocCStringArray(names)
          gtk_about_dialog_add_credit_section(state.internalWidget, sectionName.cstring, names)
  
  example:
    AboutDialog:
      programName = "My Application"
      logo = "applications-graphics"
      version = "1.0.0"
      credits = @{
        "Code": @[
          "Erika Mustermann",
          "Max Mustermann",
        ],
        "Art": @["Max Mustermann"]
      }

type ScalePosition* = enum
  ScaleLeft,
  ScaleRight,
  ScaleTop,
  ScaleBottom

proc toGtk(pos: ScalePosition): GtkPositionType =
  result = GtkPositionType(ord(pos))

type ScaleMark* = object
  label*: Option[string]
  value*: float
  position*: ScalePosition

renderable Scale of BaseWidget:
  ## A slider for choosing a numeric value within a range.
  min: float = 0 ## Lower end of the range displayed by the scale
  max: float = 100 ## Upper end of the range displayed by the scale
  value: float = 0 ## The value the Scale widget displays. Remember to update it via your `valueChanged` proc to reflect the new value on the Scale widget.
  marks: seq[ScaleMark] = @[] ## Adds marks to the Scale at points where `ScaleMark.value` would be placed. If `ScaleMark.label` is provided, it will be rendered next to the mark. `ScaleMark.position` determines the mark's position (and its label) relative to the scale. Note that ScaleLeft and ScaleRight are only sensible when the Scale is vertically oriented (`orient` = `OrientY`), while ScaleTop and ScaleBottom are only sensible when it is horizontally oriented (`orient` = `OrientX`)
  inverted: bool = false ## Determines whether the min and max value of the Scale are ordered (low value) left => right (high value) in the case of `inverted = false` or (high value) left <= right (low value) in the case of `inverted = true`.
  showValue: bool = true ## Determines whether to display the numeric value as a label on the widget (`showValue = true`) or not (`showValue = false`)
  stepSize: float = 5 ## Determines the value increment/decrement when the widget is in focus and the user presses arrow keys.
  pageSize: float = 10 ## Determines the value increment/decrement when the widget is in focus and the user presses page keys. Typically larger than stepSize.
  orient: Orient = OrientX ## The orientation of the widget. Orients the widget either horizontally (`orient = OrientX`) or vertically (`orient = OrientY`)
  showFillLevel: bool = true ## Determines whether to color the Scale from the "origin" to the place where the slider on the Scale sits. The Scale is filled left => right/top => bottom if `inverted = false` and left <= right/top <= bottom if `inverted = true`
  precision: int64 = 1 ## Number of decimal places to display for the value. `precision = 1` enables values like 1.2, while `precision = 2` enables values like 1.23 and so on.
  valuePosition: ScalePosition ## Specifies where the label of the Scale widget's value should be placed. This setting has no effect if `showValue = false`.
  
  proc valueChanged(newValue: float) ## Emitted when the range value changes from an interaction triggered by the user.

  hooks:
    beforeBuild:
      let orient: Orient = if widget.hasOrient: widget.valOrient else: OrientX
      state.internalWidget = gtk_scale_new(orient.toGtk(), nil.GtkAdjustment)

    connectEvents:
      proc valueChangedEventCallback(
        widget: GtkWidget, 
        data: ptr EventObj[proc(newValue: float)]
      ) {.cdecl.} =
        let scaleValue: float = gtk_range_get_value(widget).float
        ScaleState(data[].widget).value = scaleValue
        data[].callback(scaleValue)
        data[].redraw()
      
      state.connect(state.valueChanged, "value-changed", valueChangedEventCallback)
      
    disconnectEvents:
      disconnect(state.internalWidget, state.valueChanged)

  hooks min:
    property:
      gtk_range_set_range(state.internalWidget, state.min.cfloat, state.max.cfloat)
  
  hooks max:
    property:
      gtk_range_set_range(state.internalWidget, state.min.cfloat, state.max.cfloat)

  hooks marks:
    property:
      gtk_scale_clear_marks(state.internalWidget)
      for mark in state.marks:
        let label: string = if mark.label.isSome(): mark.label.get() else: $mark.value
        gtk_scale_add_mark(state.internalWidget, mark.value, mark.position.toGtk(), label.cstring)

  hooks value:
    property:
      gtk_range_set_value(state.internalWidget, state.value.cdouble)
    read:
      state.value = gtk_range_get_value(state.internalWidget).float
  
  hooks inverted:
    property:
      gtk_range_set_inverted(state.internalWidget, state.inverted.cbool)
  
  hooks showValue:
    property:
      gtk_scale_set_draw_value(state.internalWidget, state.showValue.cbool)

  hooks stepSize:
    property:
      gtk_range_set_increments(state.internalWidget, state.stepSize.cdouble, state.pageSize.cdouble)
  
  hooks pageSize:
    property:
      gtk_range_set_increments(state.internalWidget, state.stepSize.cdouble, state.pageSize.cdouble)
  
  hooks orient:
    property:
      gtk_orientable_set_orientation(state.internalWidget, state.orient.toGtk())

  hooks showFillLevel:
    property:
      gtk_scale_set_has_origin(state.internalWidget, state.showFillLevel.cbool)
  
  hooks precision:
    property:
      gtk_scale_set_digits(state.internalWidget, state.precision.cint)

  hooks valuePosition:
    property:
      gtk_scale_set_value_pos(state.internalWidget, state.valuePosition.toGtk())

  example:
    Scale:
      value = app.value
      showFillLevel = false
      min = 0
      max = 1
      marks = @[ScaleMark(some("Just a mark"), ScaleLeft, 0.5)]
      inverted = true
      showValue = false
      
      proc valueChanged(newValue: float) =
        echo "New value is ", newValue
        app.value = newValue


# See TODO at comment of PixbufObj regarding why we wrap GtkMediaStream with MediaStreamObj
type 
  MediaStreamObj = object
    gtk*: GtkMediaStream

  MediaStream* = ref MediaStreamObj 

crossVersionDestructor(stream, MediaStreamObj):
  if isNil(stream.gtk):
    return
  
  g_object_unref(pointer(stream.gtk))

proc `=sink`(dest: var MediaStreamObj; source: MediaStreamObj) =
  `=destroy`(dest)
  wasMoved(dest)
  dest.gtk = source.gtk
  
proc `=copy`*(dest: var MediaStreamObj, source: MediaStreamObj) =
  let areSameObject = pointer(source.gtk) == pointer(dest.gtk)
  if areSameObject:
    return
  
  `=destroy`(dest)
  wasMoved(dest)
  if not isNil(source.gtk):
    g_object_ref(pointer(source.gtk))
    
  dest.gtk = source.gtk

proc newMediaStream(gtk: GtkMediaStream): MediaStream =
  if gtk.isNil:
    raise newException(ValueError, "Unable to create MediaStream from GtkMediaStream(nil)")
  
  result = MediaStream(gtk: gtk)

proc newMediaStream*(fileName: string): MediaStream =
  if not fileExists(fileName):
    raise newException(IOError, "Unable to create MediaStream for file that does not exist: '" & fileName & "'")
  
  let gtk = gtk_media_file_new_for_filename(fileName.cstring)
  result = newMediaStream(gtk)

proc newMediaStream*(gFile: GFile): MediaStream =
  if gFile.isNil:
    raise newException(ValueError, "Unable to create MediaStream from GFile(nil)")
    
  let gtk = gtk_media_file_new_for_file(gFile)
  result = newMediaStream(gtk)

proc endStream*(stream: MediaStream) =
  when GtkMinor >= 4:
    gtk_media_stream_stream_ended(stream.gtk)
  else:
    gtk_media_stream_ended(stream.gtk)

proc loop*(stream: MediaStream): bool =
  gtk_media_stream_get_loop(stream.gtk).bool

proc playing*(stream: MediaStream): bool =
  gtk_media_stream_get_playing(stream.gtk).bool

proc hasAudio*(stream: MediaStream): bool =
  gtk_media_stream_has_audio(stream.gtk).bool

proc hasVideo*(stream: MediaStream): bool =
  gtk_media_stream_has_video(stream.gtk).bool

proc muted*(stream: MediaStream): bool =
  gtk_media_stream_get_muted(stream.gtk).bool

proc isSeekable*(stream: MediaStream): bool =
  gtk_media_stream_is_seekable(stream.gtk).bool

proc isSeeking*(stream: MediaStream): bool =
  gtk_media_stream_is_seeking(stream.gtk).bool

proc duration*(stream: MediaStream): int64 =
  gtk_media_stream_get_duration(stream.gtk)

proc hasEnded*(stream: MediaStream): bool =
  gtk_media_stream_get_ended(stream.gtk).bool

proc getError*(stream: MediaStream): GError =
  gtk_media_stream_get_error(stream.gtk)

proc timestamp*(stream: MediaStream): int64 =
  gtk_media_stream_get_timestamp(stream.gtk)

proc volume*(stream: MediaStream): float =
  gtk_media_stream_get_volume(stream.gtk).float

proc mute*(stream: MediaStream, mute: bool) = 
  gtk_media_stream_set_muted(stream.gtk, mute.cbool)

proc pause*(stream: MediaStream) =
  gtk_media_stream_pause(stream.gtk)

proc play*(stream: MediaStream) =
  gtk_media_stream_play(stream.gtk)

proc `muted=`*(stream: MediaStream, muted: bool) =
  gtk_media_stream_set_muted(stream.gtk, muted.cbool)

proc `loop=`*(stream: MediaStream, enableLooping: bool) =
  gtk_media_stream_set_loop(stream.gtk, enableLooping.cbool)

proc `playing=`*(stream: MediaStream, playing: bool) =
  gtk_media_stream_set_playing(stream.gtk, playing.cbool)

proc `volume=`*(stream: MediaStream, volume: float) =
  gtk_media_stream_set_volume(stream.gtk, volume.cdouble)

proc seek*(stream: MediaStream, timestamp: int64) =
  gtk_media_stream_seek(stream.gtk, timestamp)

proc seekRelative*(stream: MediaStream, intervalInMicroSeconds: int64) =
  let alreadySeeking = stream.isSeeking()
  if not stream.isSeekable() or alreadySeeking:
    return
  
  let timestampInMicroS = gtk_media_stream_get_timestamp(stream.gtk)
  gtk_media_stream_seek(stream.gtk, timestampInMicroS + intervalInMicroSeconds)

renderable Video of BaseWidget:
  autoplay: bool = false
  loop: bool = false
  mediaStream: MediaStream

  setter fileName: string
  setter file: GFile

  hooks:
    beforeBuild:
      state.internalWidget = gtk_video_new()
    
  hooks mediaStream:
    property:
      if isNil(state.mediaStream):
        gtk_video_set_media_stream(state.internalWidget, GtkMediaStream(nil))
      else:
        gtk_video_set_media_stream(state.internalWidget, state.mediaStream.gtk)
  
  hooks autoplay:
    property:
      gtk_video_set_autoplay(state.internalWidget, state.autoplay.cbool)

  hooks loop:
    property:
      gtk_video_set_loop(state.internalWidget, state.loop.cbool)

proc `hasFileName=`*(widget: Video, has: bool) =
  widget.hasMediaStream = has

proc `valFileName=`*(widget: Video, fileName: string) =
  if fileExists(fileName):
    widget.valMediaStream = newMediaStream(fileName)

proc `hasFile=`*(widget: Video, has: bool) =
  widget.hasMediaStream = has

proc `valFile=`*(widget: Video, file: GFile) =
  widget.valMediaStream = newMediaStream(file)

renderable Expander of BaseWidget:
  ## Container that shows or hides its child depending on whether it is expanded/collapsed 
  label: string ## Sets the clickable header of the Expander. Overwritten by `labelWidget` if it is provided via adder.
  labelWidget: Widget ## Sets the clickable header of the Expander. Overwrites `label` if provided.
  expanded: bool = false ## Determines whether the Expander body is shown (expanded = true) or not (expanded = false)
  child: Widget ## Determines the body of the Expander.
  resizeToplevel: bool = false
  useMarkup: bool = false
  useUnderline: bool = false
  
  proc activate(activated: bool) ## Triggered whenever Expander is expanded or collapsed
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_expander_new(widget.valLabel.cstring)
  
    connectEvents:
      proc activateEventCallback(
        widget: GtkWidget, 
        data: ptr EventObj[proc(activated: bool)]
      ) {.cdecl.} =
        let expanded: bool = not gtk_expander_get_expanded(widget).bool # Necessary as widget hasn't updated itself yet, thus this returns the old value
        ExpanderState(data[].widget).expanded = expanded
        data[].callback(expanded)
        data[].redraw()

      state.connect(state.activate, "activate", activateEventCallback)

    disconnectEvents:
      disconnect(state.internalWidget, state.activate)
      
  hooks label:
    property:
      gtk_expander_set_label(state.internalWidget, state.label.cstring)

  hooks expanded:
    property:
      gtk_expander_set_expanded(state.internalWidget, state.expanded.cbool)

  hooks resizeToplevel:
    property:
      gtk_expander_set_resize_toplevel(state.internalWidget, state.resizeToplevel.cbool)

  hooks useMarkup:
    property:
      gtk_expander_set_use_markup(state.internalWidget, state.useMarkup.cbool)

  hooks useUnderline:
    property:
      gtk_expander_set_use_underline(state.internalWidget, state.useUnderline.cbool)

  hooks child:
    (build, update):
      state.updateChild(state.child, widget.valChild, gtk_expander_set_child)
  
  hooks labelWidget:
    (build, update):
      state.updateChild(state.labelWidget, widget.valLabelWidget, gtk_expander_set_label_widget)
  
  adder add:
    if widget.hasChild:
      raise newException(ValueError, "Unable to add multiple children to the body of an Expander.")
    
    widget.hasChild = true
    widget.valChild = child

  adder addLabel:
    if widget.hasLabelWidget:
      raise newException(ValueError, "Unable to add multiple Labels as the header of an Expander")
    
    widget.hasLabelWidget = true
    widget.valLabelWidget = child

renderable PasswordEntry of BaseWidget:
  text: string
  # menuModel: GtkMenuModel # Not yet supported
  activatesDefault: bool = true
  placeholderText: string = "Password"
  showPeekIcon: bool = true
  
  proc activate() ## Triggered when the user "activated" the entry e.g. by hitting "enter" key while PasswordEntry is in focus. 
  proc changed(password: string) ## Triggered when the user types in the PasswordEntry.
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_password_entry_new()
    connectEvents:
      proc changedEventCallback(
        widget: GtkWidget, 
        data: ptr EventObj[proc(password: string)]
      ) {.cdecl.} =
        let password: string = $gtk_editable_get_text(widget)
        PasswordEntryState(data[].widget).text = password
        data[].callback(password)
        data[].redraw()

      state.connect(state.activate, "activate", eventCallback)
      state.connect(state.changed, "changed", changedEventCallback)
    disconnectEvents:
      disconnect(state.internalWidget, state.activate)
      disconnect(state.internalWidget, state.changed)
  
  hooks text:
    property:
      gtk_editable_set_text(state.internalWidget, state.text.cstring)
    read:
      state.text = $gtk_editable_get_text(state.internalWidget)
  
  hooks activatesDefault:
    property:
      var value = g_value_new(state.activatesDefault)
      g_object_set_property(state.internalWidget.pointer, "activates-default", value.addr)
      g_value_unset(value.addr)

  hooks placeholderText:
    property:
      var value = g_value_new(state.placeholderText)
      g_object_set_property(state.internalWidget.pointer, "placeholder-text", value.addr)
      g_value_unset(value.addr)

  hooks showPeekIcon:
    property:
      gtk_password_entry_set_show_peek_icon(state.internalWidget, state.showPeekIcon.cbool)
  
  
renderable ProgressBar of BaseWidget:
  ## A progress bar widget to show progress being made on a long-lasting task
  ellipsize: EllipsizeMode = EllipsizeEnd ## Determines how the `text` gets ellipsized if `showText = true` and `text` overflows.
  fraction: float = 0.0 ## Determines how much the ProgressBar is filled. Must be between 0.0 and 1.0. 
  inverted: bool = false
  pulseStep: float = 0.1
  showText: bool = false
  text: string = ""

  hooks:
    beforeBuild:
      state.internalWidget = gtk_progress_bar_new()
  
  hooks ellipsize:
    property:
      gtk_progress_bar_set_ellipsize(state.internalWidget, PangoEllipsizeMode(ord(state.ellipsize)))

  hooks fraction:
    property:
      gtk_progress_bar_set_fraction(state.internalWidget, state.fraction.cdouble)
  
  hooks inverted:
    property:
      gtk_progress_bar_set_inverted(state.internalWidget, state.inverted.cbool)
  
  hooks pulseStep:
    property:
      gtk_progress_bar_set_pulse_step(state.internalWidget, state.pulseStep.cdouble)
    
  hooks showText:
    property:
      gtk_progress_bar_set_show_text(state.internalWidget, state.showText.cbool)

  hooks text:
    property:
      gtk_progress_bar_set_text(state.internalWidget, state.text.cstring)

renderable ActionBar of BaseWidget:
  ## A Bar for actions to execute in a given context. Can be hidden with intro- and outro-animations.
  centerWidget: Widget
  packStart: seq[Widget] ## Widgets shown on the start of the ActionBar
  packEnd: seq[Widget] ## Widgets shown on the end of the ActionBar
  revealed: bool
  
  hooks:
    beforeBuild:
      state.internalWidget = gtk_action_bar_new()
  
  hooks centerWidget:
    (build, update):
      state.updateChild(state.centerWidget, widget.valCenterWidget, gtk_action_bar_set_center_widget)
      
  hooks packStart:
    (build, update):
      state.updateChildren(state.packStart, widget.valPackStart, gtk_action_bar_pack_start, gtk_action_bar_remove)
        
  hooks packEnd:
    (build, update):
      state.updateChildren(state.packEnd, widget.valPackEnd, gtk_action_bar_pack_end, gtk_action_bar_remove)
  
  hooks revealed:
    property:
      gtk_action_bar_set_revealed(state.internalWidget, state.revealed.cbool)
  
  adder add:
    if widget.hasCenterWidget:
      raise newException(ValueError, "Unable to add multiple children as center widget of ActionBar. Add them to the start or end via {.addStart.} or {.addEnd.}.")
    widget.hasCenterWidget = true
    widget.valCenterWidget = child
    
  adder addStart:
    widget.hasPackStart = true
    widget.valPackStart.add(child)    
  
  adder addEnd:
    widget.hasPackEnd = true
    widget.valPackEnd.add(child)
const
  ListViewRichList* = StyleClass("rich-list")
  ListViewNavigationSidebar* = StyleClass("navigation-sidebar")
  ListViewDataTable* = StyleClass("data-table")

renderable ListView of BaseWidget:
  size: int ## Number of items
  
  selectionMode: SelectionMode
  selected: HashSet[int] ## Indices of the currently selected items.
  
  showSeparators: bool = false
  singleClickActivate: bool = false
  enableRubberband: bool = false
  
  proc viewItem(index: int): Widget
  proc select(rows: HashSet[int])
  proc activate(index: int)
  
  type ItemState = object
    widgetState: WidgetState
    listItem: GtkWidget
  
  model {.private, onlyState.}: GListModel
  selectionModel {.private, onlyState.}: GtkSelectionModel
  factory {.private, onlyState.}: GtkListItemFactory
  itemStates {.private, onlyState.}: Table[int, ItemState]
  
  hooks:
    beforeBuild:
      state.factory = gtk_signal_list_item_factory_new()
      state.model = g_list_store_new(G_TYPE_OBJECT)
      state.internalWidget = gtk_list_view_new(GtkSelectionModel(nil), state.factory)
      
      type ListViewStateObj = typeof(ListViewState()[])
      
      proc bindCallback(factory: GtkListItemFactory,
                        listItem: GtkWidget,
                        stateObj: ptr ListViewStateObj) {.cdecl.} =
        let
          index = int(gtk_list_item_get_position(listItem))
          updater = stateObj[].viewItem.callback(index)
        updater.assignApp(stateObj[].app)
        let widgetState = updater.build()
        stateObj[].itemStates[index] = ItemState(
          widgetState: widgetState,
          listItem: listItem
        )
        gtk_list_item_set_child(listItem, widgetState.unwrapInternalWidget())
      
      proc unbindCallback(factory: GtkListItemFactory,
                          listItem: GtkWidget,
                          stateObj: ptr ListViewStateObj) {.cdecl.} =
        let index = int(gtk_list_item_get_position(listItem))
        stateObj[].itemStates.del(index)
      
      discard g_signal_connect(state.factory, "bind", pointer(bindCallback), state[].addr)
      discard g_signal_connect(state.factory, "unbind", pointer(unbindCallback), state[].addr)
    update:
      for index, itemState in state.itemStates.mpairs:
        let updater = state.viewItem.callback(index)
        updater.assignApp(state.app)
        let newState = updater.update(itemState.widgetState)
        if not newState.isNil:
          gtk_list_item_set_child(itemState.listItem, newState.unwrapInternalWidget())
          itemState.widgetState = newState
    connectEvents:
      proc activateCallback(widget: GtkWidget,
                            position: cuint,
                            data: ptr EventObj[proc(index: int)]) =
        data[].callback(int(position))
        data[].redraw()
      
      state.connect(state.activate, "activate", activateCallback)
      
      proc selectionChangedCallback(selectionModel: GtkSelectionModel,
                                    position: cuint,
                                    count: cuint,
                                    data: ptr EventObj[proc (rows: HashSet[int])]) {.cdecl.} =
        let state = ListViewState(data[].widget)
        for index in position..(position + count):
          if bool(gtk_selection_model_is_selected(selectionModel, index)):
            state.selected.incl(int(index))
          else:
            state.selected.excl(int(index))
        data[].callback(state.selected)
        data[].redraw()
      
      if not state.select.isNil:
        state.select.widget = state
        state.select.handler = g_signal_connect(
          state.selectionModel,
          "selection-changed",
          selectionChangedCallback,
          state.select[].addr
        )
    disconnectEvents:
      state.internalWidget.disconnect(state.activate)
      if not state.select.isNil:
        assert state.select.handler > 0
        g_signal_handler_disconnect(pointer(state.selectionModel), state.select.handler)
        state.select.handler = 0
        state.select.widget = nil
  
  # TODO: Custom List Model
  hooks size:
    build:
      for it in 0..<widget.valSize:
        g_list_store_append(state.model, pointer(state.model))
      state.size = widget.valSize
    update:
      if widget.hasSize:
        while state.size < widget.valSize:
          g_list_store_append(state.model, pointer(state.model))
          state.size += 1
        
        while state.size > widget.valSize:
          state.size -= 1
          g_list_store_remove(state.model, cuint(state.size))
  
  hooks selectionMode:
    property:
      case state.selectionMode:
        of SelectionNone:
          state.selectionModel = gtk_no_selection_new(state.model)
        of SelectionSingle:
          state.selectionModel = gtk_single_selection_new(state.model)
        of SelectionBrowse, SelectionMultiple:
          state.selectionModel = gtk_multi_selection_new(state.model)
      
      state.selected.reset()
      gtk_list_view_set_model(state.internalWidget, state.selectionModel)
  
  hooks selected:
    (build, update):
      if widget.hasSelected:
        for index in state.selected - widget.valSelected:
          gtk_selection_model_unselect_item(state.selectionModel, cuint(index))
        for index in widget.valSelected - state.selected:
          gtk_selection_model_select_item(
            state.selectionModel,
            cuint(index),
            cbool(ord(false))
          )
        state.selected = widget.valSelected
  
  hooks showSeparators:
    property:
      gtk_list_view_set_show_separators(state.internalWidget, cbool(ord(state.showSeparators)))
  
  hooks singleClickActivate:
    property:
      gtk_list_view_set_single_click_activate(state.internalWidget, cbool(ord(state.singleClickActivate)))
  
  hooks enableRubberband:
    property:
      gtk_list_view_set_enable_rubberband(state.internalWidget, cbool(ord(state.enableRubberband)))


export BaseWidget, BaseWidgetState, BaseWindow, BaseWindowState
export Window, Box, Overlay, Label, Icon, Picture, Button, HeaderBar, ScrolledWindow, Entry, Spinner
export SpinButton, Paned, ColorButton, Switch, LinkButton, ToggleButton, CheckButton, RadioGroup
export DrawingArea, GlArea, MenuButton, ModelButton, Separator, Popover, PopoverMenu
export TextView, ListBox, ListBoxRow, ListBoxRowState, FlowBox, FlowBoxChild
export Frame, DropDown, Grid, Fixed, ContextMenu, LevelBar, Calendar
export Dialog, DialogState, DialogButton
export BuiltinDialog, BuiltinDialogState
export FileChooserDialog, FileChooserDialogState
export ColorChooserDialog, ColorChooserDialogState
export MessageDialog, MessageDialogState
export AboutDialog, AboutDialogState
export buildState, updateState, assignAppEvents
export Scale
export Expander
export SearchEntry
export Video
export ProgressBar
export EmojiChooser
export EditableLabel
export PasswordEntry
export CenterBox
export ListView
export ActionBar
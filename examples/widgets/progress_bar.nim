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

import std/[sequtils]
import owlkettle, owlkettle/[dataentries, playground, adw]

viewable App:
  ellipsize: EllipsizeMode = EllipsizeEnd
  fraction: float = 0.3
  inverted: bool = false
  pulseStep: float = 0.1
  showText: bool = false
  text: string = ""
  sensitive: bool = true
  tooltip: string = ""
  sizeRequest: tuple[x, y: int] = (-1, -1)

method view(app: AppState): Widget =
  result = gui:
    Window():
      title = "ProgressBar Example"
      defaultSize = (800, 600)
      HeaderBar() {.addTitlebar.}:
        insert(app.toAutoFormMenu()) {.addRight.}
      
        Button() {.addRight.}:
          text = "+"
          style = [ButtonFlat]
          
          proc clicked() =
            if app.fraction + 0.05 <= 1.0:
              app.fraction += 0.05
          
        Button() {.addRight.}:
          text = "-"
          style = [ButtonFlat]
          
          proc clicked() =
            if app.fraction - 0.05 > 0.0:
              app.fraction -= 0.05
          
      Box(orient = OrientY):
        Label(text = "Progress Bar: ")
        ProgressBar():
          ellipsize = app.ellipsize
          fraction = app.fraction
          inverted = app.inverted
          pulseStep = app.pulseStep
          showText = app.showText
          text = app.text
          sensitive = app.sensitive
          tooltip = app.tooltip
          sizeRequest = app.sizeRequest

adw.brew(gui(App()))

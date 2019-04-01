----------------------------------------------------------------------
--
-- Button.elm
-- SVG Buttons
-- Copyright (c) 2018-2019 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------


module Svg.Button exposing
    ( Button, Content(..), Location, Size, Msg, RepeatTime(..)
    , simpleButton, repeatingButton
    , getState, setState, isTouchAware, setTouchAware, getSize, setSize
    , normalRepeatTime
    , render, renderBorder, renderContent, renderOverlay
    , update, checkSubscription
    )

{-| The `Svg.Button` module makes it easy to create SVG buttons.

Currently, the buttons are rectangular, with a two-pixel wide black border, containing either text or Svg you provide for their body. They support single clicks or repeated clicks, and work on both regular computer browsers, with a mouse, or portable browsers, with a touch screen.


# Types

@docs Button, Content, Location, Size, Msg, RepeatTime


# Constructors

@docs simpleButton, repeatingButton


# Button state accessors

@docs getState, setState, isTouchAware, setTouchAware, getSize, setSize


# Constants

@docs normalRepeatTime


# Rendering

@docs render, renderBorder, renderContent, renderOverlay


# Events

@docs update, checkSubscription

-}

import Debug exposing (log)
import Html
import Html.Events exposing (on)
import Json.Decode as JD exposing (field, float, map2)
import Svg exposing (Attribute, Svg, g, rect, text, text_)
import Svg.Attributes
    exposing
        ( dominantBaseline
        , fill
        , fillOpacity
        , fontSize
        , height
        , opacity
        , pointerEvents
        , stroke
        , strokeOpacity
        , strokeWidth
        , style
        , textAnchor
        , transform
        , width
        , x
        , y
        )
import Svg.Events exposing (onMouseDown, onMouseOut, onMouseOver, onMouseUp)
import Task
import Time exposing (Posix)


{-| Opaque internal message.

You wrap these with the `(Msg -> msg)` you pass to `render`, and pass them to `update`.

-}
type Msg
    = MouseDown
    | MouseOut
    | MouseUp
    | TouchStart
    | TouchEnd
    | Repeat
    | Subscribe Float


{-| Read a button's `state`.
-}
getState : Button state -> state
getState (Button button) =
    button.state


{-| Set a button's `state`.
-}
setState : state -> Button state -> Button state
setState state (Button button) =
    Button
        { button | state = state }


{-| Read a button's size.
-}
getSize : Button state -> Size
getSize (Button button) =
    button.size


{-| Set a button's size.
-}
setSize : Size -> Button state -> Button state
setSize size (Button button) =
    Button
        { button | size = size }


{-| Return True if a Button is touch aware.
-}
isTouchAware : Button state -> Bool
isTouchAware (Button button) =
    button.touchAware


{-| Set whether a button is touch aware.

`update` notices when it gets a touch event, and sets the `touchAware` state, but since you usually don't save updated simple buttons, the next event won't notice. Mobile browsers have a delay in generating a simulated click event. Knowing that the button is touch aware eliminates that delay, since the click is then generated by the `TouchEnd` event instead of the `MouseUp` event.

-}
setTouchAware : Bool -> Button state -> Button state
setTouchAware touchAware (Button button) =
    Button
        { button | touchAware = touchAware }


{-| Two ways to draw the button content.

`TextContent` encapsulates a `String`, which is sized to half the button height and centered.

`SvgContent` allows you to render any `Svg` you wish.

-}
type Content msg
    = TextContent String
    | SvgContent (Svg msg)


{-| A two-dimensional location: (x, y)
-}
type alias Location =
    ( Float, Float )


{-| A two-dimensional size: (width, height)
-}
type alias Size =
    ( Float, Float )


{-| An Svg Button.

Create one with `simpleButton` or `repeatingButton`.

-}
type Button state
    = Button
        { size : Size
        , repeatTime : RepeatTime
        , delay : Float
        , enabled : Bool
        , state : state
        , touchAware : Bool
        }


{-| Create a simple, rectanglar button.

It sends a `msg` when clicked or tapped.

The `view` function draws a two-pixel wide, black border around it. Your drawing function should leave room for that, or it will be overlaid.

-}
simpleButton : Size -> state -> Button state
simpleButton =
    repeatingButton NoRepeat


{-| First arg to `repeatingButton`.

The two `Float` args to `RepeatTimeWithInitialDelay` are the initial delay and the subsequent repeat period, in milliseconds.

-}
type RepeatTime
    = NoRepeat
    | RepeatTime Float
    | RepeatTimeWithInitialDelay Float Float


{-| Like `simpleButton`, but repeats the click or tap periodically, as long as the mouse or finger is held down.
-}
repeatingButton : RepeatTime -> Size -> state -> Button state
repeatingButton repeatTime size state =
    Button
        { size = size
        , repeatTime = repeatTime
        , delay = 0
        , enabled = True
        , state = state
        , touchAware = False
        }


repeatDelays : RepeatTime -> ( Float, Float )
repeatDelays repeatTime =
    case repeatTime of
        NoRepeat ->
            ( 0, 0 )

        RepeatTime delay ->
            ( delay, delay )

        RepeatTimeWithInitialDelay delay nextDelay ->
            ( delay, nextDelay )


{-| This is the usual value used for the repeat time of a repeating button.

It has an initial delay of 1/2 second and a repeat period of 1/10 second.

-}
normalRepeatTime : RepeatTime
normalRepeatTime =
    RepeatTimeWithInitialDelay 500 100


{-| Call this to process a Button message from inside your wrapper.

The `Bool` in the return value is true if this message should be interpreted as a click on the button. Simple buttons never change the button or return a command you need to care about, but you'll need to call `getState` on the button to figure out what to do (unless your application has only a single button).

-}
update : (Msg -> msg) -> Msg -> Button state -> ( Bool, Button state, Cmd msg )
update wrapper msg button =
    case msg of
        Subscribe _ ->
            ( False, button, Cmd.none )

        TouchStart ->
            case button of
                Button but ->
                    let
                        ( initialDelay, delay ) =
                            repeatDelays but.repeatTime

                        button2 =
                            Button
                                { but
                                    | touchAware = True
                                    , enabled = True
                                    , delay = delay
                                }
                    in
                    ( initialDelay > 0
                    , button2
                    , repeatCmd initialDelay wrapper
                    )

        MouseDown ->
            case button of
                Button but ->
                    let
                        ( initialDelay, delay ) =
                            repeatDelays but.repeatTime

                        button2 =
                            Button
                                { but
                                    | enabled = True
                                    , delay = delay
                                }
                    in
                    ( initialDelay > 0 && not but.touchAware
                    , button2
                    , repeatCmd initialDelay wrapper
                    )

        MouseOut ->
            case button of
                Button but ->
                    let
                        button2 =
                            Button
                                { but
                                    | enabled = False
                                    , delay = 0
                                }
                    in
                    ( False
                    , button2
                    , if but.enabled then
                        repeatCmd 0 wrapper

                      else
                        Cmd.none
                    )

        TouchEnd ->
            case button of
                Button but ->
                    let
                        button2 =
                            Button
                                { but
                                    | enabled = False
                                    , delay = 0
                                }
                    in
                    ( but.enabled && but.touchAware && but.delay <= 0
                    , button2
                    , repeatCmd 0 wrapper
                    )

        MouseUp ->
            case button of
                Button but ->
                    let
                        button2 =
                            Button
                                { but
                                    | enabled = False
                                    , delay = 0
                                }
                    in
                    ( but.enabled && not but.touchAware && but.delay <= 0
                    , button2
                    , repeatCmd 0 wrapper
                    )

        Repeat ->
            case button of
                Button but ->
                    let
                        delay =
                            if but.enabled then
                                but.delay

                            else
                                0
                    in
                    ( but.enabled
                    , Button { but | delay = delay }
                    , repeatCmd but.delay wrapper
                    )


repeatCmd : Float -> (Msg -> msg) -> Cmd msg
repeatCmd delay wrapper =
    let
        task =
            Task.succeed (Subscribe delay)
    in
    Task.perform wrapper task


{-| Subscriptions are one type of message you can get inside your wrapper.

In order to check if a message is a subscription, call `checkSubscription`. If it returns a time delay and Button message, you need to use that to create a time subscription for your application.

Simple buttons don't need subscriptions. Only repeating buttons use them.

-}
checkSubscription : Msg -> Button state -> Maybe ( Float, Msg )
checkSubscription msg button =
    case msg of
        Subscribe delay ->
            Just ( delay, Repeat )

        _ ->
            Nothing


{-| Render a button's outline, your content, and the mouse-sensitive overlay.

Does this by sizing an SVG `g` element at the `Location` you pass and the size of the `Button`, and calling `renderBorder`, `renderContent`, and `renderOverlay` inside it.

-}
render : Location -> Content msg -> (Msg -> msg) -> Button state -> Svg msg
render ( xf, yf ) content wrapper button =
    case button of
        Button but ->
            let
                ( xs, ys ) =
                    ( String.fromFloat xf, String.fromFloat yf )

                ( wf, hf ) =
                    but.size

                ( ws, hs ) =
                    ( String.fromFloat wf, String.fromFloat hf )
            in
            g
                [ transform ("translate(" ++ xs ++ " " ++ ys ++ ")")
                ]
                [ renderBorder button
                , renderContent content button
                , renderOverlay wrapper button
                ]


{-| An attribute to disable mouse selection of an SVG element.

`renderContent` includes this.

From <https://www.webpagefx.com/blog/web-design/disable-text-selection/>. Thank you to Jacob Gube.

-}
disableSelection : Attribute msg
disableSelection =
    style <|
        -- Firefox
        "-moz-user-select: none;"
            -- Internet Explorer
            ++ "-ms-user-select: none;"
            -- KHTML browsers (e.g. Konqueror)
            ++ "-khtml-user-select: none;"
            -- Chrome, Safari, and Opera
            ++ "-webkit-user-select: none;"
            --  Disable Android and iOS callouts*
            ++ "-webkit-touch-callout: none;"
            -- Prevent resizing text to fit
            -- https://stackoverflow.com/questions/923782
            ++ "webkit-text-size-adjust: none;"


{-| Draw a button's transparent, mouse/touch-sensitive overlay.

You won't usually use this, letting `render` call it for you.

You should call this AFTER drawing your button, so that the overlay is the last thing drawn. Otherwise, it may not get all the mouse/touch events.

-}
renderOverlay : (Msg -> msg) -> Button state -> Svg msg
renderOverlay wrapper (Button button) =
    let
        but =
            Button button

        ( w, h ) =
            button.size

        ws =
            String.fromFloat w

        hs =
            String.fromFloat h
    in
    Svg.rect
        [ x "0"
        , y "0"
        , width ws
        , height hs
        , opacity "0"
        , fillOpacity "1"
        , onTouchStart (\touch -> wrapper TouchStart)
        , onMouseDown (wrapper MouseDown)
        , onTouchEnd (\touch -> wrapper TouchEnd)
        , onMouseUp (wrapper MouseUp)
        , onMouseOut (wrapper MouseOut)
        , disableSelection
        ]
        []


{-| Draw a button's border.

You won't usually use this, letting `render` call it for you.

You should call this BEFORE drawing your button, so that its opaque body does not cover your beautiful drawing.

-}
renderBorder : Button state -> Svg msg
renderBorder (Button button) =
    let
        ( w, h ) =
            button.size

        ws =
            String.fromFloat (w - 2)

        hs =
            String.fromFloat (h - 2)
    in
    Svg.rect
        [ x "1"
        , y "1"
        , width ws
        , height hs
        , stroke "black"
        , fill "white"
        , strokeWidth "2"
        , opacity "1"
        , strokeOpacity "1"
        ]
        []


{-| Render the visible, non-border part of a button.

You won't usually use this, letting `render` call it for you.

But you could use it for a non-button, if you just want some text centered in a rectangle.

-}
renderContent : Content msg -> Button state -> Svg msg
renderContent content (Button button) =
    g [ disableSelection ]
        [ let
            ( xf, yf ) =
                button.size

            yfo2s =
                String.fromFloat (yf / 2)

            xfo2s =
                String.fromFloat (xf / 2)
          in
          case content of
            TextContent string ->
                text_
                    [ fill "black"
                    , fontSize yfo2s
                    , x xfo2s
                    , y yfo2s
                    , textAnchor "middle"
                    , dominantBaseline "middle"
                    ]
                    [ text string ]

            SvgContent svg ->
                svg
        ]



---
--- From https://github.com/knledg/touch-events/blob/master/src/TouchEvents.elm
--- Copied, so I don't have to wait for that project to upgrade.
---


{-| event decoder
-}
eventDecoder : (Touch -> msg) -> String -> JD.Decoder msg
eventDecoder msg eventKey =
    JD.at [ eventKey, "0" ] (JD.map msg touchDecoder)


{-| touch decoder
-}
touchDecoder : JD.Decoder Touch
touchDecoder =
    map2 Touch
        (field "clientX" float)
        (field "clientY" float)


{-| Type alias for the touch record on the touch event object
-}
type alias Touch =
    { clientX : Float
    , clientY : Float
    }


{-| Lower level "touchend" event handler
Takes the application `Msg` type which should take `TouchEvents.Touch`
as a payload

    type Msg
        = UserSwipeEnd TouchEvents.Touch

    view model =
        div
            [ TouchEvents.onTouchEnd UserSwipeEnd
            ]
            []

-}
onTouchEnd : (Touch -> msg) -> Html.Attribute msg
onTouchEnd msg =
    on "touchend" <| eventDecoder msg "changedTouches"


{-| Lower level "touchstart" event handler
Takes the application `Msg` type which should take `TouchEvents.Touch`
as a payload

    type Msg
        = UserSwipeStart TouchEvents.Touch

    view model =
        div
            [ TouchEvents.onTouchStart UserSwipeStart
            ]
            []

-}
onTouchStart : (Touch -> msg) -> Html.Attribute msg
onTouchStart msg =
    on "touchstart" <| eventDecoder msg "touches"


{-| Lower level "touchmove" event handler
-}
onTouchMove : (Touch -> msg) -> Html.Attribute msg
onTouchMove msg =
    on "touchmove" <| eventDecoder msg "touches"

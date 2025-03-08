unit Menus;

{$mode objfpc}{$H+}

interface

uses
  Windows, Natives, ctypes;

type
  TMenuItemStyle = (misSimple, misActive, misTitle);

procedure Mnu_SetStatusText(str: string; time: DWORD = 2500; isGxtEntry: boolean = false);
procedure Mnu_UpdateStatusText;
procedure Mnu_Beep;
procedure Mnu_DrawRect(A_0, A_1, A_2, A_3: cfloat; a_4, A_5, A_6, A_7: cint);
procedure Mnu_DrawLine(caption: string; lineWidth, lineHeight, lineTop, lineLeft, textLeft: cfloat; style: TMenuItemStyle; rescaleText: boolean = true);

implementation

const
  // Color vectors (RGBA)
  title_color_bg: array [0..3] of cint = (16, 0, 177, 255);
  title_color_text: array [0..3] of cint = (255, 255, 255, 255);
  active_color_bg: array [0..3] of cint = (189, 208, 238, 255);
  active_color_text: array [0..3] of cint = (0, 0, 0, 255);
  simple_color_bg: array [0..3] of cint = (16, 107, 177, 255);
  simple_color_text: array [0..3] of cint = (255, 255, 255, 255);

var
  statusText: string;
  statusTextDrawTicksMax: DWORD;
  statusTextGxtEntry: boolean;

procedure Mnu_SetStatusText(str: string; time: DWORD = 2500; isGxtEntry: boolean = false);
begin
  statusText := str;
  statusTextDrawTicksMax := GetTickCount + time;
  statusTextGxtEntry := isGxtEntry;
end;

procedure Mnu_UpdateStatusText;
begin
  if (GetTickCount < statusTextDrawTicksMax) and (statusText <> '') then
     begin
       SET_TEXT_FONT(0);
       SET_TEXT_SCALE(0.55, 0.55);
       SET_TEXT_COLOUR(255, 255, 255, 255);
       SET_TEXT_WRAP(0.0, 1.0);
       SET_TEXT_CENTRE(BOOL(1));
       SET_TEXT_DROPSHADOW(0, 0, 0, 0, 0);
       SET_TEXT_EDGE(1, 0, 0, 0, 205);
       if statusTextGxtEntry then
          _SET_TEXT_ENTRY(PChar(statusText))
       else
          begin
            _SET_TEXT_ENTRY(PChar('STRING'));
            ADD_TEXT_COMPONENT_SUBSTRING_PLAYER_NAME(PChar(statusText));
          end;
       _DRAW_TEXT(0.5, 0.5);
     end
  else
     statusText := '';
end;

procedure Mnu_Beep;
begin
  PLAY_SOUND_FRONTEND(-1, PChar('NAV_UP_DOWN'), PChar('HUD_FRONTEND_DEFAULT_SOUNDSET'), BOOL(0));
end;

procedure Mnu_DrawRect(A_0, A_1, A_2, A_3: cfloat; a_4, A_5, A_6, A_7: cint);
begin
  DRAW_RECT(A_0 + (A_2 / 2), A_1 + (A_3 / 2), A_2, A_3, A_4, A_5, A_6, A_7);
end;

procedure Mnu_DrawLine(caption: string; lineWidth, lineHeight, lineTop, lineLeft, textLeft: cfloat; style: TMenuItemStyle; rescaleText: boolean = true);
var
  font, screen_w, screen_h, num25: cint;
  text_scale, lineWidthScaled, lineTopScaled, textLeftScaled, lineHeightScaled, lineLeftScaled: cfloat;
  text_col, rect_col: array [0..3] of cint;
begin
  // Defaults to most cases
  text_scale := 0.35;
  font := 0;
  // Cases
  case style of
       misSimple:
         begin
           text_col := simple_color_text;
           rect_col := simple_color_bg;
         end;
       misActive:
         begin
           text_col := active_color_text;
           rect_col := active_color_bg;
         end;
       misTitle:
         begin
           font := 1;
           if rescaleText then
              text_scale := 0.5;
           text_col := title_color_text;
           rect_col := title_color_bg;
         end;
  end;
  // Code

  GET_SCREEN_RESOLUTION(@screen_w, @screen_h);

  textLeft:= textLeft + lineLeft;

  lineWidthScaled := lineWidth / screen_w; // line width
  lineTopScaled := lineTop / screen_h; // line top offset
  textLeftScaled := textLeft / screen_w; // text left offset
  lineHeightScaled := lineHeight / screen_h; // line height
  lineLeftScaled := lineLeft / screen_w;

  // this is how it's done in original scripts

  // _GET_TEXT_SCREEN_LINE_COUNT
  num25 := _0x9040DFB09BE75706(textLeftScaled, lineTopScaled + 0.00278 + lineHeightScaled - 0.005);

  // rect
  Mnu_DrawRect(lineLeftScaled, lineTopScaled + 0.00278, lineWidthScaled, (num25 * _GET_TEXT_SCALE_HEIGHT(text_scale, 0)) + lineHeightScaled + 0.005, rect_col[0], rect_col[1], rect_col[2], rect_col[3]);

  SET_TEXT_FONT(font);
  SET_TEXT_SCALE(0.0, text_scale);
  SET_TEXT_COLOUR(text_col[0], text_col[1], text_col[2], text_col[3]);
  SET_TEXT_CENTRE(BOOL(0));
  SET_TEXT_DROPSHADOW(0, 0, 0, 0, 0);
  SET_TEXT_EDGE(0, 0, 0, 0, 0);
  _SET_TEXT_ENTRY(PChar('STRING'));
  ADD_TEXT_COMPONENT_SUBSTRING_PLAYER_NAME(PChar(caption));
  _DRAW_TEXT(textLeftScaled, lineTopScaled + 0.00278 - 0.005);
end;

end.


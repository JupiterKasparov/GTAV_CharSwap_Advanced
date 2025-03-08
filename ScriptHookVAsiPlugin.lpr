library ScriptHookVAsiPlugin;

{$mode objfpc}
{$H+}

uses
  Windows, ctypes, ScriptHookV, Natives, IniFiles, Menus, shlobj, SysUtils, DOM, XMLRead, Classes;

type
  TPlayerData = record
    Health, Armor, MaxHealth, WantedLevel: cint;
    Weapons: array of record
      WeaponHash: Hash;
      Ammo: cint;
      TintIndex: cint;
      Components: array of Hash;
    end;
    WantedStatus: BOOL;
  end;

  TPlayerCharData = record
      ModelName: string;
      OrigHash, ChangedHash: Hash;
  end;

  eMenuKey = (mkNone, mkUp, mkDown, mkBack, mkSelect);

const
  sct_CharacterConversions: string = 'CharacterConversions';
  sct_InGameDataLists: string = 'InGameDataLists';
  sct_Keys: string = 'Keys';
  sct_TransformationOptions = 'TransformationOptions';
  lines_0: array [0..3] of string = ('Addon ped selector', 'Ped selector', 'Reset skin', 'Set current skin as default');

var
  settings: TIniFile;
  {Keys}
  action_key: DWORD;
  action_key_state: boolean;
  {Transformation options}
  fearful_trans: boolean;
  {Character changed data}
  character_is_changed: boolean;
  {Menu handling data}
  menu_level, menu_index, menu_group: integer;
  menu_visible: boolean;
  activate_menu_hash: Hash;
  menu_activate_key: DWORD;
  current_menu_key: eMenuKey;

{************************
 These are used to determine the current player, and their related properties
 ************************}
var
  players_initialized: boolean = false;
  PlayersData: array [0..2] of TPlayerCharData =
    (
     (ModelName: 'player_zero'; OrigHash: 0; ChangedHash: 0),
     (ModelName: 'player_one'; OrigHash: 0; ChangedHash: 0),
     (ModelName: 'player_two'; OrigHash: 0; ChangedHash: 0)
    );

function GetPlayerIndex(plyr: Player): integer;
var
  i: integer;
  p: Ped;
begin
  // Calculate player models hashes when needed
  if not players_initialized then
     begin
       players_initialized := true;
       for i := 0 to High(PlayersData) do
         begin
           PlayersData[i].OrigHash := GET_HASH_KEY(PChar(PlayersData[i].ModelName));
           PlayersData[i].ChangedHash := GET_HASH_KEY(PChar(settings.ReadString(sct_CharacterConversions, PlayersData[i].ModelName, '')));
         end;
     end;
  // Get current player index (not the same as GTAV player index!)
  p := GET_PLAYER_PED(plyr);
  Result := -1;
  for i := 0 to High(PlayersData) do
      if (IS_PED_MODEL(p, PlayersData[i].OrigHash) <> BOOL(0)) or
         (IS_PED_MODEL(p, PlayersData[i].ChangedHash) <> BOOL(0)) then
            exit(i);
end;

{************************
 Data!
 ************************}
var
  AddonPedNames, PedModelNames, WeaponNames, WeaponCompNames: TStrings;

// Gets the Addon peds from the AddonPeds XML file. It is in the PEDS.META format
procedure RegisterAddonPeds(lst: TStrings);
const
  doc_path: array [0..MAX_PATH - 1] of char = '';
var
  ap_m_name: string;
  ap_m: TXMLDocument;
  initDataList, itemList, propertiesList: TDomNodeList;
  i, j, k: integer;
begin
  lst.Clear;
  if (SHGetFolderPath(0, CSIDL_PERSONAL, 0, SHGFP_TYPE_CURRENT, doc_path) = S_OK) then
     begin
       ap_m_name := Format('%s\Rockstar Games\GTA V\UserMods\ap_m.xml', [doc_path]);
       if FileExists(ap_m_name) then
          begin
            ap_m := nil;
            try
              try
                ReadXMLFile(ap_m, ap_m_name);
                initDataList := nil;
                try
                  initDataList := ap_m.DocumentElement.GetElementsByTagName('InitDatas');
                  for i := 0 to initDataList.Count - 1 do
                    begin
                      itemList := nil;
                      try
                        itemList := initDataList[i].ChildNodes;
                        for j := 0 to itemList.Count - 1 do
                          if (itemList[j].NodeName = 'Item') then
                             begin
                               propertiesList := nil;
                               try
                                 propertiesList := itemList[j].ChildNodes;
                                 for k := 0 to propertiesList.Count - 1 do
                                   if (propertiesList[k].NodeName = 'Name') then
                                      begin
                                        lst.Add(propertiesList[k].TextContent);
                                        break;
                                      end;
                               finally
                                 if Assigned(propertiesList) then
                                    propertiesList.Free;
                               end;
                             end;
                      finally
                        if Assigned(itemList) then
                           itemList.Free;
                      end;
                    end;
                finally
                  if Assigned(initDataList) then
                     initDataList.Free;
                end;
              finally
                if Assigned(ap_m) then
                   ap_m.Free;
              end;
            except
              lst.Clear;
            end;
          end;
     end;
end;

{************************
 UI TEXTBOX (above map)
 ************************}
procedure PlayerNotify(msg: string);
begin
  _SET_NOTIFICATION_TEXT_ENTRY('STRING');
  ADD_TEXT_COMPONENT_SUBSTRING_PLAYER_NAME(PChar(msg));
  _DRAW_NOTIFICATION(BOOL(0), BOOL(0));
end;

{************************
 These functions will handle the storing of player properties. That is, because eberything is removed from playef upon transformation,
 and we need to restore everything!
 ************************}
function StorePlayerData(plyr: Player): TPlayerData;
var
  i, j: integer;
  wk, ck: Hash;
  p: Ped;
begin
  p := GET_PLAYER_PED(plyr);
  SetLength(Result.Weapons, 0);
  for i := 0 to WeaponNames.Count - 1 do
      begin
        wk := GET_HASH_KEY(PChar(WeaponNames[i]));
        if (IS_WEAPON_VALID(wk) <> BOOL(0)) and (HAS_PED_GOT_WEAPON(p, wk, BOOL(0)) <> BOOL(0)) then
         begin
           SetLength(Result.Weapons, Length(Result.Weapons) + 1);
           with Result.Weapons[High(Result.Weapons)] do
                begin
                  WeaponHash := wk;
                  Ammo := GET_AMMO_IN_PED_WEAPON(p, WeaponHash);
                  TintIndex := GET_PED_WEAPON_TINT_INDEX(p, WeaponHash);
                  SetLength(Components, 0);
                  for j := 0 to WeaponCompNames.Count - 1 do
                    begin
                      ck := GET_HASH_KEY(PChar(WeaponCompNames[j]));
                      if (HAS_PED_GOT_WEAPON_COMPONENT(p, WeaponHash, ck) <> BOOL(0)) then
                         begin
                           SetLength(Components, Length(Components) + 1);
                           Components[High(Components)] := ck;
                         end;
                    end;
                end;
         end;
      end;
  Result.WantedStatus := ARE_PLAYER_FLASHING_STARS_ABOUT_TO_DROP(plyr);
  Result.WantedLevel := GET_PLAYER_WANTED_LEVEL(plyr);
  Result.MaxHealth := GET_PED_MAX_HEALTH(p);
  Result.Health := GET_ENTITY_HEALTH(p);
  if (Result.Health > Result.MaxHealth) then
     Result.MaxHealth := Result.Health;
  Result.Armor := GET_PED_ARMOUR(p);
end;

procedure RestorePlayerData(plyr: Player; data: TPlayerData);
const
  msg_noweapon: string = '~r~As an animal, you cannot have weapons or armor!';
var
  i, j: integer;
  p: Ped;
begin
  p := GET_PLAYER_PED(plyr);
  if (data.WantedStatus = BOOL(0)) and (GET_PLAYER_WANTED_LEVEL(plyr) <= 0) then
     begin
       SET_PLAYER_WANTED_LEVEL(plyr, data.WantedLevel, BOOL(0));
       SET_PLAYER_WANTED_LEVEL_NOW(plyr, BOOL(0));
     end;
  SET_PED_MAX_HEALTH(p, data.MaxHealth);
  SET_ENTITY_HEALTH(p, data.Health);
  if (IS_PED_HUMAN(p) <> BOOL(0)) then
          begin
            SET_PED_ARMOUR(p, data.Armor);
            for i := 0 to High(data.Weapons) do
                begin
                  REQUEST_WEAPON_ASSET(data.Weapons[i].WeaponHash, 31, 0);
                  while (HAS_WEAPON_ASSET_LOADED(data.Weapons[i].WeaponHash) = BOOL(0)) do
                        ScriptHookVWait(0);
                  GIVE_WEAPON_TO_PED(p, data.Weapons[i].WeaponHash, data.Weapons[i].Ammo, BOOL(0), BOOL(0));
                  SET_PED_WEAPON_TINT_INDEX(p, data.Weapons[i].WeaponHash, data.Weapons[i].TintIndex);
                  for j := 0 to High(data.Weapons[i].Components) do
                      GIVE_WEAPON_COMPONENT_TO_PED(p, data.Weapons[i].WeaponHash, data.Weapons[i].Components[j]);
                  REMOVE_WEAPON_ASSET(data.Weapons[i].WeaponHash);
                end;
          end
  // As an animal, you cannot keep your weapons or armor!!!
  // That is, because only chimpanzees can use the weapons, while in case of other animals,
  // weapons can cause bugs, or even game crash!
  else if (data.Armor > 0) or (Length(data.Weapons) > 0) then
     begin
       if menu_visible then
          Mnu_SetStatusText(msg_noweapon)
       else
          PlayerNotify(msg_noweapon);
     end;
end;

procedure DeletePlayerData(data: TPlayerData);
var
  i: integer;
begin
  for i := 0 to High(data.Weapons) do
      SetLength(data.Weapons[i].Components, 0);
  SetLength(data.Weapons, 0);
end;

{************************
 Purple explosion effect, that is playede, when player is transformed!
 ************************}
procedure ActorTransformationEffect(p: Ped);
const
  asset = 'scr_rcbarry2';
  effect = 'scr_clown_appears';
begin
  REQUEST_NAMED_PTFX_ASSET(asset);
  while (HAS_NAMED_PTFX_ASSET_LOADED(asset) = BOOL(0)) do
        ScriptHookVWait(0);
  _SET_PTFX_ASSET_NEXT_CALL(asset);
  START_PARTICLE_FX_NON_LOOPED_ON_ENTITY(effect, p, 0, 0, 0, 0, 0, 0, 1.0, BOOL(0),BOOL(0), BOOL(0));
  ScriptHookVWait(150); // We must wait a bit before changing player - otherwise the effect is not played
  _REMOVE_NAMED_PTFX_ASSET(asset);
end;

{************************
 Nearby peds will fear of purple explosion!
 ************************}
procedure FleePeds(plyr: Player; radius: cfloat);
var
  p: Ped;
  peds: array [0..127] of Ped;
  i: integer;
  pedloc, ploc: Vector3;
  dist, xd, yd, zd: cfloat;
  count, fears: cint;
begin
  p := GET_PLAYER_PED(plyr);
  count := worldGetAllPeds(pcint(peds), Length(peds));
  ploc := GET_ENTITY_COORDS(p, BOOL(0));
  fears := 0;
  for i := 0 to min(High(peds), count - 1) do
      if (peds[i] <> p) and (IS_ENTITY_A_PED(peds[i]) <> BOOL(0)) and (GET_INTERIOR_FROM_ENTITY(p) = GET_INTERIOR_FROM_ENTITY(peds[i])) then
         begin
           pedloc := GET_ENTITY_COORDS(peds[i], BOOL(0));
           xd := ploc.x - pedloc.x;
           yd := ploc.y - pedloc.y;
           zd := ploc.z - pedloc.z;
           dist := System.sqrt((xd * xd) + (yd * yd) + (zd * zd)); // Pascal sqrt is faster than GTAV sqrt
           if (dist < radius) then
              begin
                if (IS_PED_HUMAN(peds[i]) <> BOOL(0)) then
                   inc(fears);
                TASK_REACT_AND_FLEE_PED(peds[i], p); // Ped will fear of player when seeing transformation
              end;
         end;
  if (fears >= 5) and (GET_INTERIOR_FROM_ENTITY(p) = 0) then
     REPORT_CRIME(plyr, 43, GET_WANTED_LEVEL_THRESHOLD(1));
end;

{************************
 Changes the player hash
 ************************}
procedure SetPlayerHash(p: Ped; h: Hash);
var
  baseaddr: ptruint;
  info1: ptruint;
begin
  baseaddr := ptruint(getScriptHandleBaseAddress(p));
  info1 := pptruint(baseaddr + $20)^;
  PHash(info1 + $18)^ := h;
end;

{************************
 Sets the player's character and hash. Performs fearful transformation, if required!
 ************************}
function SwapCharacter(plyr: Player; oldChar, newChar: Hash; bChangeHash, bFearful: boolean): boolean;
var
  p: Ped;
  saved: TPlayerData;
begin
  p := GET_PLAYER_PED(plyr);
  // Request model, and check validity
  REQUEST_MODEL(newChar);
  Result := (IS_MODEL_VALID(newChar) <> BOOL(0)) and (IS_MODEL_IN_CDIMAGE(newChar) <> BOOL(0));
  if Result then
     begin
       // Wait for model
       while HAS_MODEL_LOADED(newChar) = BOOL(0) do
             ScriptHookVWait(0);
       // Store data
       saved := StorePlayerData(plyr);
       // Effect
       ActorTransformationEffect(p);
       // Change model and hash
       SET_PLAYER_MODEL(plyr, newChar);
       p := GET_PLAYER_PED(plyr);
       SET_PED_DEFAULT_COMPONENT_VARIATION(p);
       if bChangeHash then
          SetPlayerHash(p, oldChar);
       // Fearful effect
       if bFearful then
          FleePeds(plyr, 17.5);
       // Restore data
       RestorePlayerData(plyr, saved);
       // Free memory
       DeletePlayerData(saved);
     end;
  SET_MODEL_AS_NO_LONGER_NEEDED(newChar);
end;

{************************
 Returns the player's current situation!
 ************************}
function IsPlayerReady(plyr: Player): byte;
var
  p: Ped;
begin
  p := GET_PLAYER_PED(plyr);
  if (IS_PLAYER_PLAYING(plyr) = BOOL(0)) or (IS_PLAYER_CONTROL_ON(plyr) = BOOL(0)) or (IS_PED_DEAD_OR_DYING(p, BOOL(1) <> BOOL(0))) or (IS_PLAYER_READY_FOR_CUTSCENE(plyr) = BOOL(0)) then
     Result := 1  // Dead or non-controllable
  else if (IS_PED_BEING_STUNNED(p, 0) <> BOOL(0)) or (IS_PLAYER_BEING_ARRESTED(plyr, BOOL(1)) <> BOOL(0)) then
     Result := 2  // Blocked!
  else if (IS_ENTITY_IN_AIR(p) <> BOOL(0)) or (IS_PED_CLIMBING(p) <> BOOL(0)) or (IS_PED_ON_FOOT(p) = BOOL(0)) then
     Result := 3  // To prevent death
  else if (GET_MISSION_FLAG <> BOOL(0)) or (GET_RANDOM_EVENT_FLAG <> 0) then
     Result := 4 // On mission
  else
     Result := 0;
end;

{************************
 Auto-performs some tasks, if the player is an animal.
 ************************}
procedure CheckPlayerAnimal(plyr: Player);
var
  p: Ped;
  idx: integer;
begin
  p := GET_PLAYER_PED(plyr);
  if (IS_PED_HUMAN(p) = BOOL(0)) then
     begin
       // When you die as a fish, you'll get into a loop, where you will die over and over, because you are a fish,
       // and the hospital is not in water! - To prevent this, turn back to human, if playing as an animal!
       if (IS_PLAYER_PLAYING(plyr) = BOOL(0)) then
          begin
            idx := GetPlayerIndex(plyr);
            if (idx >= 0) then
               begin
                 SwapCharacter(plyr, 0, PlayersData[idx].OrigHash, false, false);
                 character_is_changed := false;
               end;
          end
       // Otherwise disable some features
       else
          begin
            // No vehicle enter as animal!
            if (IS_PED_GETTING_INTO_A_VEHICLE(p) <> BOOL(0)) then
               TASK_LEAVE_ANY_VEHICLE(p, 0, 0);
          end;
     end;
end;

{************************
 This will save the current player skin as default.
 ************************}
procedure SavePlayerCharModel(plyr: Player);
var
  i, idx: integer;
  h: Hash;
begin
  idx := GetPlayerIndex(plyr);
  // Player must be Micheal, Franklin, or Trevor!
  if (idx >= 0) then
     begin
       h := PlayersData[idx].ChangedHash;
       // Check skin validity
       for i := 0 to High(PlayersData) do
           if (PlayersData[i].OrigHash = h) then
              begin
                Mnu_SetStatusText('~r~You cannot save your original player model!');
                exit;
              end;
       // Check in IG Peds list
       for i := 0 to PedModelNames.Count - 1 do
           if (GET_HASH_KEY(PChar(PedModelNames[i])) = h) then
              begin
                settings.WriteString(sct_CharacterConversions, PlayersData[idx].ModelName, PedModelNames[i]);
                Mnu_SetStatusText('~g~Ped model successfully saved!');
                exit;
              end;
       // Check in Addon Peds list
       for i := 0 to AddonPedNames.Count - 1 do
           if (GET_HASH_KEY(PChar(AddonPedNames[i])) = h) then
              begin
                settings.WriteString(sct_CharacterConversions, PlayersData[idx].ModelName, AddonPedNames[i]);
                Mnu_SetStatusText('~g~Addon ped model successfully saved!');
                exit;
              end;
     end;
end;

{************************
 Selected model hash by menu
 ************************}
function GetSelectedModelHash: Hash;
var
  gid: integer;
begin
  gid := menu_group * 30;
  case menu_level of
       3: Result := GET_HASH_KEY(PChar(AddonPedNames[gid + menu_index]));
       4: Result := GET_HASH_KEY(PChar(PedModelNames[gid + menu_index]));
       else
         Result := 0;
  end;
end;

{************************
 Gets if the selected model is already used or not
 ************************}
function IsModelUsedByOthers(plyr: Player; h: Hash): boolean;
var
  i, idx: integer;
begin
  idx := GetPlayerIndex(plyr);
  for i := 0 to High(PlayersData) do
      if (PlayersData[i].OrigHash = h) then
         exit(true);
  for i := 0 to High(PlayersData) do
      if (PlayersData[i].ChangedHash = h) and (i <> idx) then
         exit(true);
  Result := false;
end;

{************************
 GROUPING FUNCTIONS
 ************************}
function TotalGroupCount(total: integer): integer;
var
  gc: integer;
begin
  // Total group count
  gc := (total div 30);
  if ((total - (gc * 30)) > 0) then
     inc(gc);
  Result := gc;
end;

function GetGroupCount(index, total: integer): integer;
var
  gc: integer;
begin
  gc := TotalGroupCount(total);
  if (index < gc) then
     Result := 30
  else if (index > gc) then
     Result := 0
  else
     Result := total - ((gc - 1) * 30);
end;

{************************
 MENU DISPLAY FUNCTION
 ************************}
procedure DrawMenu;
var
  i: integer;
  elm_style: TMenuItemStyle;
  gid, gcount: integer;
begin
  case menu_level of
       // Main menu
       0:
         begin
           Mnu_DrawLine('Jupiter''s Character Swapper', 300.0, 18.0, 8.0, 8.0, 0.0, misTitle, true);
           for i := 0 to High(lines_0) do
             begin
               elm_style := misSimple;
               if (menu_index = i) then
                  elm_style := misActive;
               Mnu_DrawLine(lines_0[i], 300.0, 18.0, 26.0 + (i * 18.0), 8.0, 0.0, elm_style, false);
             end;
         end;
       // Skin changer groups (addon peds). 30 items per group.
       1:
         begin
           gcount := TotalGroupCount(AddonPedNames.Count);
           Mnu_DrawLine('Addon ped groups', 300.0, 18.0, 8.0, 8.0, 0.0, misTitle, true);
           for i := 0 to gcount - 1 do
             begin
               elm_style := misSimple;
               if (menu_index = i) then
                  elm_style := misActive;
               Mnu_DrawLine(Format('Addon ped group %d (%d peds)', [i + 1, GetGroupCount(i + 1, AddonPedNames.Count)]), 300.0, 18.0, 26.0 + (i * 18.0), 8.0, 0.0, elm_style, false);
             end;
         end;
       // Skin changer groups (game peds).
       2:
         begin
           gcount := TotalGroupCount(PedModelNames.Count);
           Mnu_DrawLine('Ped groups', 300.0, 18.0, 8.0, 8.0, 0.0, misTitle, true);
           for i := 0 to gcount - 1 do
             begin
               elm_style := misSimple;
               if (menu_index = i) then
                  elm_style := misActive;
               Mnu_DrawLine(Format('Ped group %d (%d peds)', [i + 1, GetGroupCount(i + 1, PedModelNames.Count)]), 300.0, 18.0, 26.0 + (i * 18.0), 8.0, 0.0, elm_style, false);
             end;
         end;
       // Skin submenu (addon peds). Maximum 30 items!
       3:
         begin
           gid := menu_group * 30;
           gcount := GetGroupCount(menu_group + 1, AddonPedNames.Count);
           Mnu_DrawLine(Format('Addon ped group %d', [menu_group + 1]), 300.0, 18.0, 8.0, 8.0, 0.0, misTitle, true);
           for i := 0 to gcount - 1 do
             begin
               elm_style := misSimple;
               if (menu_index = i) then
                  elm_style := misActive;
                Mnu_DrawLine(AddonPedNames[gid + i], 300.0, 18.0, 26.0 + (i * 18.0), 8.0, 0.0, elm_style, false);
             end;
         end;
       // Skin submenu (Peds). Maximum is 30 items!
       4:
         begin
           gid := menu_group * 30;
           gcount := GetGroupCount(menu_group + 1, PedModelNames.Count);
           Mnu_DrawLine(Format('Ped group %d', [menu_group + 1]), 300.0, 18.0, 8.0, 8.0, 0.0, misTitle, true);
           for i := 0 to gcount - 1 do
             begin
               elm_style := misSimple;
               if (menu_index = i) then
                  elm_style := misActive;
               Mnu_DrawLine(PedModelNames[gid + i], 300.0, 18.0, 26.0 + (i * 18.0), 8.0, 0.0, elm_style, false);
             end;
         end;
  end;
end;

{************************
 MAIN SCRIPT FUNCTION
 ************************}
procedure ScriptMain; cdecl;
var
  plyr: Player;
  index, menu_max: integer;
  h: Hash;
begin
  activate_menu_hash := GET_HASH_KEY(PChar('jupiter swapper menu'));
  menu_visible := false;
  // Get action key
  action_key := settings.ReadInteger(sct_Keys, 'TransformKey', $2E);
  menu_activate_key := settings.ReadInteger(sct_Keys, 'MenuActivateKey', -1);
  // Fearful transformation enabled?
  fearful_trans := settings.ReadBool(sct_TransformationOptions, 'FearfulTransformation', false);
  // Script logic
  character_is_changed := false;
  while true do
        begin
          plyr := GET_PLAYER_INDEX;
          index := GetPlayerIndex(plyr);
          // ****
          // Hide menu on player switch. Also, the player is automatically reset by the game.
          // ****
          if (IS_PLAYER_SWITCH_IN_PROGRESS <> BOOL(0)) then
             begin
               character_is_changed := false;
               menu_visible := false;
             end
          // ****
          // If the menu is visible then do menu stuff, like drawing menu, handle menu keypresses, etc.
          // ****
          else if menu_visible then
             begin
               // ****
               // MENU ACTION HANDLER
               // ****
               case current_menu_key of
                    mkUp:
                      if (menu_index > 0) then
                         begin
                           Mnu_Beep;
                           dec(menu_index);
                         end;
                    mkDown:
                      begin
                        menu_max := 0;
                        case menu_level of
                             0: menu_max := High(lines_0);
                             1: menu_max := TotalGroupCount(AddonPedNames.Count) - 1;
                             2: menu_max := TotalGroupCount(PedModelNames.Count) - 1;
                             3: menu_max := GetGroupCount(menu_group + 1, AddonPedNames.Count) - 1;
                             4: menu_max := GetGroupCount(menu_group + 1, PedModelNames.Count) - 1;
                        end;
                        if (menu_index < menu_max) then
                           begin
                             Mnu_Beep;
                             inc(menu_index);
                           end;
                      end;
                    mkBack:
                      begin
                        Mnu_Beep;
                        case menu_level of
                             0: menu_visible := false;
                             1, 2:
                               begin
                                 menu_index := 0;
                                 menu_level := 0;
                               end;
                             3:
                               begin
                                 menu_index := menu_group;
                                 menu_level := 1;
                               end;
                             4:
                               begin
                                 menu_index := menu_group;
                                 menu_level := 2;
                               end;
                        end;
                      end;
                    mkSelect:
                      begin
                        case menu_level of
                             0:
                               // Main menu menu-points handler!
                               case menu_index of
                                    0:
                                      begin
                                        if (AddonPedNames.Count > 0) then
                                           begin
                                             menu_level := 1;
                                             menu_index := 0;
                                             menu_group := 0;
                                             Mnu_Beep;
                                           end
                                        else
                                           Mnu_SetStatusText('~r~No addon peds found!');
                                      end;
                                    1:
                                      begin
                                        if (PedModelNames.Count > 0) then
                                           begin
                                             menu_level := 2;
                                             menu_index := 0;
                                             menu_group := 0;
                                             Mnu_Beep;
                                           end
                                        else
                                           Mnu_SetStatusText('~r~No peds found! Ped list either has wrong format, or may not be present!');
                                      end;
                                    2:
                                      if character_is_changed then
                                         begin
                                           case IsPlayerReady(plyr) of
                                                0:
                                                  begin
                                                    SwapCharacter(plyr, 0, PlayersData[index].OrigHash, false, fearful_trans);
                                                    character_is_changed := false;
                                                  end;
                                                2: Mnu_SetStatusText('~r~Your current situation is so awkward!');
                                                3: Mnu_SetStatusText('~r~Finish any activities before trying to do this!');
                                                4: Mnu_SetStatusText('~r~It seems, you are on mission, or a random event is ongoing!?');
                                           end;
                                         end
                                      else
                                         Mnu_SetStatusText('~g~You''re already playing as normal player ped!');
                                    3:
                                      if character_is_changed then
                                         SavePlayerCharModel(plyr)
                                      else
                                         Mnu_SetStatusText('~r~You cannot save your normal player model!');
                               end;
                             1:
                               // Addon peds groups handler!
                               begin
                                 menu_group := menu_index;
                                 menu_index := 0;
                                 menu_level := 3;
                                 Mnu_Beep;
                               end;
                             2:
                               // Ig peds groups handler
                               begin
                                 menu_group := menu_index;
                                 menu_index := 0;
                                 menu_level := 4;
                                 Mnu_Beep;
                               end;
                             3:
                               // Addon peds content handler
                               if (IsPlayerReady(plyr) = 0) then
                                  begin
                                    h := GetSelectedModelHash;
                                    if IsModelUsedByOthers(plyr, h) then
                                       Mnu_SetStatusText('~r~This addon ped is already used by another protagonist!')
                                    else
                                       begin
                                         PlayersData[index].ChangedHash := h;
                                         if SwapCharacter(plyr, PlayersData[index].OrigHash, PlayersData[index].ChangedHash, true, fearful_trans) then
                                            character_is_changed := true
                                         else
                                            Mnu_SetStatusText('~r~Invalid addon ped model!');
                                       end;
                                  end
                               else
                                  Mnu_SetStatusText('~r~You''re too busy now!');
                             4:
                               // Ig peds content handler
                               if (IsPlayerReady(plyr) = 0) then
                                  begin
                                    h := GetSelectedModelHash;
                                    if IsModelUsedByOthers(plyr, h) then
                                       Mnu_SetStatusText('~r~This ped is already used by another protagonist!')
                                    else
                                       begin
                                         PlayersData[index].ChangedHash := h;
                                         if SwapCharacter(plyr, PlayersData[index].OrigHash, PlayersData[index].ChangedHash, true, fearful_trans) then
                                            character_is_changed := true
                                         else
                                            Mnu_SetStatusText('~r~Invalid ped model!');
                                       end;
                                  end
                               else
                                  Mnu_SetStatusText('~r~You should wait until you are not so busy!');
                        end;
                      end;
               end;
               current_menu_key := mkNone;
               DrawMenu;
             end
          // ****
          // If the menu is NOT visible, we can check if the cheat has been entered or not.
          // ****
          else if (_HAS_CHEAT_STRING_JUST_BEEN_ENTERED(activate_menu_hash) <> BOOL(0)) and not menu_visible then
             begin
               menu_visible := true;
               menu_level := 0;
               menu_index := 0;
               current_menu_key := mkNone;
             end
          // ****
          // THE ORIGINAL SCRIPT
          // ****
          else if action_key_state then
             begin
               if (index < 0) then
                  PlayerNotify('~r~Cannot get current player!')
               else if (PlayersData[index].ChangedHash = 0) then
                  PlayerNotify('~r~Can''t change to an empty model!')
               else if (PlayersData[index].OrigHash = PlayersData[index].ChangedHash) then
                  PlayerNotify('~r~Your original model and preferred model must be different!')
               else if IsModelUsedByOthers(plyr, PlayersData[index].ChangedHash) then
                  PlayerNotify('~r~Your preferred model is already used by another protagonist!')
               else
                  begin
                    case IsPlayerReady(plyr) of
                         0:
                           begin
                             character_is_changed := not character_is_changed;
                             if character_is_changed then
                                begin
                                  character_is_changed := SwapCharacter(plyr, PlayersData[index].OrigHash, PlayersData[index].ChangedHash, true, fearful_trans);
                                  if not character_is_changed then
                                     PlayerNotify('~r~Cannot change to invalid!');
                                end
                             else
                                SwapCharacter(plyr, 0, PlayersData[index].OrigHash, false, fearful_trans);
                           end;
                         2: PlayerNotify('~r~Cannot change in this awkward situation!');
                         3: PlayerNotify('~r~Cannot change your model right now!');
                         4: PlayerNotify('~r~Maybe you''re on a mission, or a random event is going on!?');
                    end;
                  end;
               while action_key_state do
                     ScriptHookVWait(0);
             end;
          // ****
          // Fix animal-related problems
          // ****
          if character_is_changed then
             CheckPlayerAnimal(plyr);
          // ****
          // MUST WAIT
          // ****
          Mnu_UpdateStatusText;
          ScriptHookVWait(0);
        end;
end;

{************************
 KEY HANDLER
 ************************}

procedure KeyHandler(key: DWORD; repeats: WORD; scanCode: BYTE; isExtended, isWithAlt, wasDownBefore, isUpNow: BOOL); cdecl;
begin
  if menu_visible then
     begin
       if (isUpNow <> BOOL(0)) and (wasDownBefore <> BOOL(0)) then
          begin
            case key of
                  VK_NUMPAD8: current_menu_key := mkUp;
                  VK_NUMPAD2: current_menu_key := mkDown;
                  VK_NUMPAD5: current_menu_key := mkSelect;
                  VK_NUMPAD0, VK_BACK: current_menu_key := mkBack;
            end;
          end;
     end
  else if (key = menu_activate_key) and (menu_activate_key >= 0) then
     menu_visible := true
  else if (key = action_key) and (action_key >= 0) then
     action_key_state := isUpNow = BOOL(0);
end;

{************************
 PLUGIN INITIALIZATION AND FINALIZATION CODE
 ************************}

procedure EndDll(reason: PtrInt);
begin
  // Unregister script
  scriptUnregister(HInstance);
  keyboardHandlerUnregister(@KeyHandler);
  // Free datas
  settings.Free;
  AddonPedNames.Free;
  PedModelNames.Free;
  WeaponNames.Free;
  WeaponCompNames.Free;
end;

{$R *.res}

begin
  settings := TIniFile.Create('Jupiter_CharSwap_1.ini');
  // Init datas
  AddonPedNames := TStringList.Create;
  RegisterAddonPeds(AddonPedNames);
  PedModelNames := TStringList.Create;
  ExtractStrings([','], [' ', #9], PChar(settings.ReadString(sct_InGameDataLists, 'IgPeds', '')), PedModelNames, false);
  WeaponNames := TStringList.Create;
  ExtractStrings([','], [' ', #9], PChar(settings.ReadString(sct_InGameDataLists, 'IgWeapons', '')), WeaponNames, false);
  WeaponCompNames := TStringList.Create;
  ExtractStrings([','], [' ', #9], PChar(settings.ReadString(sct_InGameDataLists, 'IgWeaponComponents', '')), WeaponCompNames, false);
  // Functions assign + Register script
  Dll_Process_Detach_Hook := @EndDll;
  keyboardHandlerRegister(@KeyHandler);
  scriptRegister(HInstance, @ScriptMain);
end.


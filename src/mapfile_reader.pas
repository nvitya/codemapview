unit mapfile_reader;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TMapEntryType = (metSection, metObject, metSymbol);
  TStringArray = array of string;

  TMapEntry = record
    EntryType: TMapEntryType;
    SectionName: string;
    ObjectName: string;
    SymbolName: string;
    Size: Integer;
    VMA: string;
  end;

  TMapEntryArray = array of TMapEntry;

  
{ TMapFile }


  TMapFile = class
  public
    Items: TMapEntryArray;

    filename : string;

    constructor Create;

    procedure LoadFromFile(const AFileName: string);
  end;

var
  mapfile: TMapFile;

implementation

//uses Math;

function SplitLine(const S: string): TStringArray;
var
  i, j: Integer;
begin
  result := [];
  //SetLength(Result, 0);
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] <= ' ' then Inc(i)
    else
    begin
      j := i;
      while (j <= Length(S)) and (S[j] > ' ') do Inc(j);
      SetLength(Result, Length(Result) + 1);
      Result[Length(Result) - 1] := Copy(S, i, j - i);
      i := j;
    end;
  end;
end;

{ TMapFile }


function CleanSymbolName(const S: string): string;
var
  i, Num, ZPos: Integer;
  Part, BaseName: string;
  IsText: Boolean;
begin
  Result := S;
  BaseName := S;
  IsText := False;
  
  if Pos('.text.', BaseName) = 1 then 
  begin
    IsText := True;
    BaseName := Copy(BaseName, 7, Length(BaseName));
  end
  else if Pos('.data.', BaseName) = 1 then BaseName := Copy(BaseName, 7, Length(BaseName))
  else if Pos('.bss.', BaseName) = 1 then BaseName := Copy(BaseName, 6, Length(BaseName))
  else if Pos('.rodata.', BaseName) = 1 then BaseName := Copy(BaseName, 9, Length(BaseName))
  else Exit;

  ZPos := Pos('_Z', BaseName);
  if ZPos = 1 then
  begin
    i := 3;
    if (i <= Length(BaseName)) and (BaseName[i] = 'N') then Inc(i)
    else if (i <= Length(BaseName)) and (BaseName[i] = 'L') then Inc(i);
    
    Result := '';
    while i <= Length(BaseName) do
    begin
      if BaseName[i] in ['0'..'9'] then
      begin
        Num := 0;
        while (i <= Length(BaseName)) and (BaseName[i] in ['0'..'9']) do
        begin
          Num := Num * 10 + (Ord(BaseName[i]) - Ord('0'));
          Inc(i);
        end;
        if (Num > 0) and (i + Num - 1 <= Length(BaseName)) then
        begin
          Part := Copy(BaseName, i, Num);
          if Result <> '' then Result := Result + '::';
          Result := Result + Part;
          Inc(i, Num);
        end
        else Break;
      end
      else Break;
    end;
    
    if Result = '' then Result := BaseName
    else if IsText then Result := Result + '()';
  end
  else
  begin
    Result := BaseName;
    if IsText and (Pos('(', Result) = 0) then Result := Result + '()';
  end;
end;

constructor TMapFile.Create;
begin
  filename := '';
end;

procedure TMapFile.LoadFromFile(const AFileName: string);
var
  Lines: TStringList;
  i, j, InMapPhase, FormatDet: Integer;
  Line, TextPart, CurSection, CurObject, TempStr: string;
  S_VMA, S_Size: string;
  EntrySize, IndentLevel, Idx: Integer;
  ET: TMapEntryType;
  Parts, NextParts: TStringArray;
begin

  filename := AFileName;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(AFileName);
    SetLength(Items, 0);
    CurSection := '';
    CurObject := '';
    
    // Auto-detect format
    FormatDet := 0; // 0=unknown, 1=flat, 2=gcc, 3=wasm, 4=arm
    for i := 0 to Lines.Count - 1 do
    begin
      if Pos('      VMA      LMA', Lines[i]) = 1 then FormatDet := 1;
      if Pos('Archive member included', Lines[i]) = 1 then FormatDet := 2;
      if Pos('Allocating common symbols', Lines[i]) = 1 then FormatDet := 2;
      if Pos('Linker script and memory map', Lines[i]) = 1 then FormatDet := 2;
      if Pos('    Addr      Off     Size Out     In      Symbol', Lines[i]) = 1 then FormatDet := 3;
      if Pos('Component: ARM Compiler', Lines[i]) = 1 then FormatDet := 4;
      if FormatDet > 0 then Break;
      if i > 20000 then Break;
    end;
    if FormatDet = 0 then FormatDet := 1; // fallback to flat
    
    if FormatDet = 1 then
    begin
      // --- ORIGINAL FLAT PARSER ---
      for i := 0 to Lines.Count - 1 do
      begin
        Line := Lines[i];
        if Length(Line) <= 33 then Continue;
        
        // Skip the header line if present
        if Pos('VMA', Copy(Line, 1, 8)) > 0 then Continue;
        
        S_VMA := Trim(Copy(Line, 1, 8));
        S_Size := Trim(Copy(Line, 19, 8));
        
        TextPart := Copy(Line, 34, Length(Line) - 33);
        IndentLevel := Length(TextPart) - Length(TrimLeft(TextPart));
        TextPart := Trim(TextPart);
        
        if TextPart = '' then Continue;
        
        if IndentLevel = 0 then
        begin
          CurSection := TextPart;
          CurObject := '';
          ET := metSection;
        end
        else if IndentLevel = 8 then
        begin
          if Pos(':(', TextPart) > 0 then
          begin
            CurObject := Copy(TextPart, 1, Pos(':(', TextPart) - 1);
            TextPart := Copy(TextPart, Pos(':(', TextPart) + 2, Length(TextPart));
            if (Length(TextPart) > 0) and (TextPart[Length(TextPart)] = ')') then
              TextPart := Copy(TextPart, 1, Length(TextPart) - 1);
          end
          else
          begin
            CurObject := TextPart;
          end;
          ET := metObject;
        end
        else
        begin
          ET := metSymbol;
        end;
        
        EntrySize := 0;
        if S_Size <> '' then
        begin
          try
            EntrySize := StrToInt('$' + S_Size);
          except
            EntrySize := 0;
          end;
        end;
        
        if EntrySize = 0 then Continue;
        
        Idx := Length(Items);
        
        // Merge logic for flat maps to avoid duplicates
        if (ET = metSymbol) and (Idx > 0) and (Items[Idx-1].EntryType = metObject) and 
           (Items[Idx-1].Size = EntrySize) then
        begin
          // If it looks like the symbol for the previous object, just upgrade the previous one
          Items[Idx-1].SymbolName := TextPart;
          Items[Idx-1].EntryType := metSymbol;
        end
        else
        begin
          SetLength(Items, Idx + 1);
          Items[Idx].EntryType := ET;
          Items[Idx].SectionName := CurSection;
          Items[Idx].ObjectName := CurObject;
          Items[Idx].SymbolName := TextPart;
          Items[Idx].Size := EntrySize;
          Items[Idx].VMA := S_VMA;
        end;
      end;
    end
    else if FormatDet = 2 then
    begin
      // --- NEW GCC MAP PARSER ---
      InMapPhase := 0;
      i := 0;
      while i < Lines.Count do
      begin
        Line := Lines[i];
        if Pos('Linker script and memory map', Line) = 1 then
        begin
          InMapPhase := 1; 
          Inc(i); Continue;
        end;
        if InMapPhase = 0 then 
        begin
          Inc(i); Continue;
        end;
        if Line = '' then 
        begin
          Inc(i); Continue;
        end;

        if not (Line[1] in [' ', #9]) then
        begin
          Parts := SplitLine(Line);
          if (Length(Parts) >= 3) and (Pos('0x', Parts[1]) = 1) then
            CurSection := Parts[0]
          else if Length(Parts) = 1 then
            CurSection := Parts[0];
          Inc(i); Continue;
        end;

        if (Length(Line) > 1) and (Line[1] = ' ') and (Line[2] <> ' ') then
        begin
          Parts := SplitLine(Line);
          if Length(Parts) = 0 then 
          begin
            Inc(i); Continue;
          end;
          if Parts[0] = '*fill*' then 
          begin
            Inc(i); Continue;
          end;
          if Pos('*(', Parts[0]) = 1 then 
          begin
            Inc(i); Continue;
          end;

          if (Length(Parts) >= 4) and (Pos('0x', Parts[1]) = 1) then
          begin
            CurObject := Parts[3];
            EntrySize := StrToIntDef('$' + Copy(Parts[2], 3, 255), 0);
            if EntrySize > 0 then 
            begin
              Idx := Length(Items);
              SetLength(Items, Idx + 1);
              Items[Idx].EntryType := metObject;
              Items[Idx].SectionName := CurSection;
              Items[Idx].ObjectName := CurObject;
              Items[Idx].SymbolName := Parts[0];
              Items[Idx].Size := EntrySize;
              Items[Idx].VMA := Parts[1];
            end;
          end
          else if Length(Parts) = 1 then
          begin
            if i + 1 < Lines.Count then
            begin
              NextParts := SplitLine(Lines[i + 1]);
              if (Length(NextParts) >= 3) and (Pos('0x', NextParts[0]) = 1) and (Pos('.o', NextParts[2]) > 0) then
              begin
                CurObject := NextParts[2];
                EntrySize := StrToIntDef('$' + Copy(NextParts[1], 3, 255), 0);
                if EntrySize > 0 then
                begin
                  Idx := Length(Items);
                  SetLength(Items, Idx + 1);
                  Items[Idx].EntryType := metObject;
                  Items[Idx].SectionName := CurSection;
                  Items[Idx].ObjectName := CurObject;
                  Items[Idx].SymbolName := Parts[0];
                  Items[Idx].Size := EntrySize;
                  Items[Idx].VMA := NextParts[0];
                end;
                Inc(i); // skip the wrapped line
              end;
            end;
          end;
          Inc(i); Continue;
        end;

        if Pos('                0x', Line) = 1 then
        begin
          Parts := SplitLine(Line);
          if Length(Parts) >= 2 then
          begin
            Idx := Length(Items);
            
            S_VMA := Parts[0];
            j := Pos(S_VMA, Line) + Length(S_VMA);
            while (j <= Length(Line)) and (Line[j] <= ' ') do Inc(j);
            TextPart := Copy(Line, j, Length(Line) - j + 1);
            
            if (Idx > 0) and (Items[Idx-1].EntryType = metObject) and 
               (Items[Idx-1].VMA = S_VMA) and (Items[Idx-1].SymbolName <> '') and 
               (Items[Idx-1].SymbolName[1] = '.') then
            begin
              Items[Idx-1].SymbolName := TextPart;
              Items[Idx-1].EntryType := metSymbol;
            end
            else
            begin
              SetLength(Items, Idx + 1);
              Items[Idx].EntryType := metSymbol;
              Items[Idx].SectionName := CurSection;
              Items[Idx].ObjectName := CurObject;
              Items[Idx].SymbolName := TextPart;
              Items[Idx].Size := 0; // standard map file symbols often don't have explicit size here
              Items[Idx].VMA := S_VMA;
            end;
          end;
        end;
        Inc(i);
      end;

    end
    else if FormatDet = 3 then
    begin
      // --- LLD Wasm Map Parser ---
      for i := 0 to Lines.Count - 1 do
      begin
        Line := Lines[i];
        if Length(Line) < 27 then Continue;
        if Pos('    Addr', Line) = 1 then Continue; // Skip header

        S_VMA := Trim(Copy(Line, 1, 8));
        if S_VMA = '-' then S_VMA := '0';
        
        S_Size := Trim(Copy(Line, 19, 8));
        
        TempStr := Copy(Line, 28, Length(Line) - 27);
        IndentLevel := Length(TempStr) - Length(TrimLeft(TempStr));
        TempStr := Trim(TempStr);
        
        if TempStr = '' then Continue;
        
        if IndentLevel = 0 then
        begin
          CurSection := TempStr;
          CurObject := '';
          ET := metSection;
        end
        else if IndentLevel = 8 then
        begin
          if Pos(':(', TempStr) > 0 then
          begin
            CurObject := Copy(TempStr, 1, Pos(':(', TempStr) - 1);
            TempStr := Copy(TempStr, Pos(':(', TempStr) + 2, Length(TempStr));
            if (Length(TempStr) > 0) and (TempStr[Length(TempStr)] = ')') then
              TempStr := Copy(TempStr, 1, Length(TempStr) - 1);
          end
          else
          begin
            CurObject := TempStr;
          end;
          ET := metObject;
        end
        else
        begin
          ET := metSymbol;
        end;

        EntrySize := 0;
        if S_Size <> '' then
        begin
          try
            EntrySize := StrToInt('$' + S_Size);
          except
            EntrySize := 0;
          end;
        end;

        if EntrySize = 0 then Continue;

        Idx := Length(Items);
        
        if (ET = metSymbol) and (Idx > 0) and (Items[Idx-1].EntryType = metObject) and 
           (Items[Idx-1].Size = EntrySize) then
        begin
          Items[Idx-1].SymbolName := TempStr;
          Items[Idx-1].EntryType := metSymbol;
        end
        else
        begin
          SetLength(Items, Idx + 1);
          Items[Idx].EntryType := ET;
          Items[Idx].SectionName := CurSection;
          Items[Idx].ObjectName := CurObject;
          Items[Idx].SymbolName := TempStr;
          Items[Idx].Size := EntrySize;
          Items[Idx].VMA := S_VMA;
        end;
      end;
    end
    else if FormatDet = 4 then
    begin
      // --- ARM Compiler Map Parser ---
      InMapPhase := 0;
      for i := 0 to Lines.Count - 1 do
      begin
        Line := Lines[i];
        if Pos('Image Symbol Table', Line) > 0 then
        begin
          InMapPhase := 1;
          Continue;
        end;
        if Pos('Memory Map of the image', Line) > 0 then
        begin
          InMapPhase := 0;
          Break;
        end;

        if InMapPhase = 1 then
        begin
          if (Length(Line) > 60) and (Pos('    ', Line) = 1) and (Pos('Symbol Name', Line) = 0) then
          begin
            NextParts := SplitLine(Line);
            if Length(NextParts) >= 4 then
            begin
              if NextParts[Length(NextParts) - 3] = 'Code' then
                j := Length(NextParts) - 5
              else
                j := Length(NextParts) - 4;
                
              if (j >= 1) and (Pos('0x', NextParts[j]) = 1) then
              begin
                S_VMA := NextParts[j];
                S_Size := NextParts[Length(NextParts) - 2];
                CurObject := NextParts[Length(NextParts) - 1];
                
                TextPart := NextParts[0];
                for IndentLevel := 1 to j - 1 do
                  TextPart := TextPart + ' ' + NextParts[IndentLevel];
                  
                IndentLevel := Pos('(', CurObject);
                if IndentLevel > 0 then
                begin
                  CurSection := Copy(CurObject, IndentLevel + 1, Length(CurObject) - IndentLevel);
                  if (Length(CurSection) > 0) and (CurSection[Length(CurSection)] = ')') then
                    SetLength(CurSection, Length(CurSection) - 1);
                  CurObject := Copy(CurObject, 1, IndentLevel - 1);
                end
                else
                begin
                  CurSection := '';
                end;
                
                EntrySize := StrToIntDef(S_Size, 0);
                if EntrySize > 0 then
                begin
                  Idx := Length(Items);
                  SetLength(Items, Idx + 1);
                  
                  if NextParts[j + 1] = 'Section' then
                    Items[Idx].EntryType := metObject
                  else
                    Items[Idx].EntryType := metSymbol;
                    
                  Items[Idx].SectionName := CurSection;
                  Items[Idx].ObjectName := CurObject;
                  Items[Idx].SymbolName := TextPart;
                  Items[Idx].Size := EntrySize;
                  Items[Idx].VMA := S_VMA;
                end;
              end;
            end;
          end;
        end;
      end;
    end;
  // Final pass to demangle unmerged object names and upgrade them to symbols
    for i := 0 to High(Items) do
    begin
      if Items[i].EntryType = metObject then
      begin
        if (Pos('.text.', Items[i].SymbolName) = 1) or
           (Pos('.data.', Items[i].SymbolName) = 1) or
           (Pos('.bss.', Items[i].SymbolName) = 1) or
           (Pos('.rodata.', Items[i].SymbolName) = 1) then
        begin
          Items[i].SymbolName := CleanSymbolName(Items[i].SymbolName);
          Items[i].EntryType := metSymbol;
        end;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

initialization
  mapfile := TMapFile.Create;

finalization
  mapfile.Free;

end.

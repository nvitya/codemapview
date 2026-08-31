program mapfiledump;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, mapfile_reader;

var
  i: Integer;
  me: TMapEntry;
  typeStr: string;
begin
  if ParamCount < 1 then
  begin
    Writeln('Usage: mapfiledump <mapfile>');
    Halt(1);
  end;

  if not FileExists(ParamStr(1)) then
  begin
    Writeln('Error: File not found: ', ParamStr(1));
    Halt(1);
  end;

  try
    mapfile.LoadFromFile(ParamStr(1));
    
    // Writeln('Type', #9, 'VMA', #9, 'Size', #9, 'Section', #9, 'Object', #9, 'Symbol');
    for i := 0 to High(mapfile.Items) do
    begin
      me := mapfile.Items[i];
      case me.EntryType of
        metSection: typeStr := 'Section';
        metObject:  typeStr := 'Object';
        metSymbol:  typeStr := 'Symbol';
      end;
      
      Writeln(typeStr, #9, me.VMA, #9, me.Size, #9, me.SectionName, #9, me.ObjectName, #9, me.SymbolName);
    end;
  except
    on E: Exception do
    begin
      Writeln('Error parsing map file: ', E.Message);
      Halt(1);
    end;
  end;
end.

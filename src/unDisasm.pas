unit unDisasm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Process;

procedure ShowDisassembly(const AElfFile, AVMA: string; ASize: Integer);

implementation

procedure ShowDisassembly(const AElfFile, AVMA: string; ASize: Integer);
var
  F: TForm;
  M: TMemo;
  VMAVal: Int64;
  ObjdumpCmd: string;
  OutputStr: string;
  RunSuccess: Boolean;
begin
  if Pos('0x', AVMA) = 1 then
    VMAVal := StrToInt64Def('$' + Copy(AVMA, 3, Length(AVMA)), 0)
  else
    VMAVal := StrToInt64Def('$' + AVMA, 0);

  F := TForm.Create(Application);
  try
    F.Caption := 'Disassembly - VMA: ' + AVMA + ' Size: ' + IntToStr(ASize);
    F.Width := 800;
    F.Height := 600;
    F.Position := poScreenCenter;
    
    M := TMemo.Create(F);
    M.Parent := F;
    M.Align := alClient;
    M.ScrollBars := ssBoth;
    M.ReadOnly := True;
    M.Font.Name := 'Courier New';
    M.Font.Size := 10;
    M.WordWrap := False;
    
    ObjdumpCmd := 'arm-none-eabi-objdump';
    
    // Attempt to run arm-none-eabi-objdump
    RunSuccess := RunCommand(ObjdumpCmd, 
      ['-d', 
       '--start-address=0x' + IntToHex(VMAVal, 8),
       '--stop-address=0x' + IntToHex(VMAVal + ASize, 8),
       AElfFile], 
      OutputStr);
      
    if not RunSuccess then
    begin
      // Fallback to objdump
      ObjdumpCmd := 'objdump';
      RunSuccess := RunCommand(ObjdumpCmd, 
        ['-d', 
         '--start-address=0x' + IntToHex(VMAVal, 8),
         '--stop-address=0x' + IntToHex(VMAVal + ASize, 8),
         AElfFile], 
        OutputStr);
    end;
    
    if RunSuccess then
      M.Text := OutputStr
    else
      M.Text := 'Error: Could not run objdump or arm-none-eabi-objdump.';
    
    F.Show;
  except
    F.Free;
  end;
end;

end.

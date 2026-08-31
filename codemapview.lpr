program codemapview;
{$mode objfpc}{$H+}
uses
  Interfaces, Forms, main;
begin
  RequireDerivedFormResource:=True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.

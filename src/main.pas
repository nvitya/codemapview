unit main;

{$mode objfpc}{$H+}

interface

uses
  mapfile_reader, Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Grids, StdCtrls,
  ExtCtrls, unDisasm;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    BtnLoad: TButton;
    cbCode: TCheckBox;
    cbData: TCheckBox;
    cbOther: TCheckBox;
    CmbFilter: TComboBox;
    edName : TEdit;
    edObject : TEdit;
    Label1 : TLabel;
    Label2 : TLabel;
    Label3 : TLabel;
    Label4 : TLabel;
    lbName : TLabel;
    lbObject : TLabel;
    lbType: TLabel;
    OpenDialog1: TOpenDialog;
    pnlTop: TPanel;
    PanelBottom: TPanel;
    grid: TStringGrid;
    cbDebug : TCheckBox;
    btnReload : TButton;
    txtSelectedSize : TStaticText;
    txtRowCount : TStaticText;
    txtListedSize : TStaticText;
    procedure BtnLoadClick(Sender: TObject);
    procedure CmbFilterChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDropFiles(Sender : TObject; const FileNames : array of string
      );
    procedure gridCompareCells(Sender: TObject; ACol, ARow, BCol,
      BRow: Integer; var Result: integer);
    procedure gridDblClick(Sender : TObject);
    procedure gridHeaderClick(Sender: TObject; IsColumn: Boolean;
      Index: Integer);
    procedure gridSelection(Sender: TObject; aCol, aRow: Integer);
    procedure btnReloadClick(Sender : TObject);
    procedure UpdateFilters(Sender : TObject; var Key : Word;
      Shift : TShiftState);
  private
    
    FLastSortCol: Integer;
    FSortAscending: Boolean;
    procedure LoadMapFile(const AFileName: string);
    procedure PopulateGrid;
    procedure OpenDisassemblyView;
    procedure UpdateSelectedSize;
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

const size_col_idx = 2;
const vma_col_idx = 5;
const name_col_idx = 3;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FLastSortCol := size_col_idx;
  FSortAscending := False;
  
  grid.Options := grid.Options + [goColSizing, goRowSelect, goHeaderHotTracking];

  if (ParamCount >= 1) and FileExists(ParamStr(1))
  then
      LoadMapFile(ParamStr(1));
end;

procedure TfrmMain.FormDropFiles(Sender : TObject; const FileNames : array of string);
begin
  if FileExists(FileNames[0]) then LoadMapFile(FileNames[0]);
end;

procedure TfrmMain.BtnLoadClick(Sender: TObject);
begin
  if OpenDialog1.Execute then
    LoadMapFile(OpenDialog1.FileName);
end;

procedure TfrmMain.btnReloadClick(Sender : TObject);
begin
  if mapfile.filename <> ''
  then
      LoadMapFile(mapfile.filename);
end;

procedure TfrmMain.UpdateFilters(Sender : TObject; var Key : Word; Shift : TShiftState);
begin
  PopulateGrid;
end;


procedure TfrmMain.CmbFilterChange(Sender: TObject);
begin
  PopulateGrid;
end;

procedure TfrmMain.LoadMapFile(const AFileName: string);
begin
  Caption := ExtractFileName(AFileName);
  mapfile.LoadFromFile(AFileName);
  PopulateGrid;
end;

procedure TfrmMain.PopulateGrid;
var
  i           : Integer;
  FilterIdx   : Integer;
  me          : TMapEntry;
  sname, sobjfile : string;
  rowidx      : integer;
  prev_rowidx : integer;
  flt_name, flt_obj : string;

  totalsize    : int64;
begin
  FilterIdx := CmbFilter.ItemIndex;

  flt_name := edName.Text;
  flt_obj  := edObject.Text;

  totalsize := 0;

  grid.BeginUpdate;
  try
    rowidx := 1;
    prev_rowidx := grid.Row;

    grid.RowCount := 1;

    for i := 0 to High(mapfile.Items) do
    begin
      me := mapfile.Items[i];

      // Filtering
      
      if me.Size = 0 then Continue;  // skip zero size entries

      if (FilterIdx = 1) and (me.EntryType <> metSection) then Continue;
      if (FilterIdx = 2) and (me.EntryType <> metObject) then Continue;
      if (FilterIdx = 3) and (me.EntryType <> metSymbol) then Continue;
      
      if (Pos('.debug', me.SectionName) = 1) and not cbDebug.Checked
      then
          continue;

      if (Pos('.text', me.SectionName) = 1) or (Pos('CODE', me.SectionName) = 1) then
      begin
        if not cbCode.Checked then Continue;
      end
      else if (Pos('.data', me.SectionName) = 1) or (Pos('.bss', me.SectionName) = 1)
              or (Pos('DATA', me.SectionName) = 1) then
      begin
        if not cbData.Checked then Continue;
      end
      else
      begin
        if not cbOther.Checked then Continue;
      end;

      if me.EntryType = metSection then sname := me.SectionName
                                   else sname := me.SymbolName;
      sobjfile := me.ObjectName;

      if (flt_name <> '') and (sname.IndexOf(flt_name) < 0) then  Continue;
      if (flt_obj  <> '') and (sobjfile.IndexOf(flt_obj) < 0) then  Continue;

      // Filling

      if grid.RowCount <= rowidx then grid.RowCount := rowidx + 1;
      
      case me.EntryType of
        metSection: grid.Cells[0, rowidx] := 'Section';
        metObject:  grid.Cells[0, rowidx] := 'Object';
        metSymbol:  grid.Cells[0, rowidx] := 'Symbol';
      end;
      grid.Cells[1, rowidx] := me.SectionName;
      grid.Cells[size_col_idx, rowidx] := IntToStr(me.Size);
      grid.Cells[name_col_idx, rowidx] := sname;
      grid.Cells[4, rowidx] := sobjfile;
      grid.Cells[5, rowidx] := me.VMA;

      totalsize += me.Size;

      rowidx += 1;
    end;
    
    // Re-apply sort if needed
    if FLastSortCol >= 0 then
    begin
      if FSortAscending then
        grid.SortOrder := soAscending
      else
        grid.SortOrder := soDescending;
      grid.SortColRow(True, FLastSortCol);
    end;

    if grid.RowCount > rowidx then grid.RowCount := rowidx;
    if prev_rowidx > rowidx - 1 then grid.Row := rowidx - 1
                                else grid.Row := prev_rowidx;

  finally
    grid.EndUpdate;
  end;

  txtListedSize.Caption := IntToStr(totalsize);
  txtRowCount.Caption := IntToStr(rowidx - 1);

  UpdateSelectedSize;
end;

procedure TfrmMain.gridCompareCells(Sender: TObject; ACol, ARow, BCol,
  BRow: Integer; var Result: integer);
var
  ValA, ValB: Integer;
begin
  if ACol = size_col_idx then // Size
  begin
    ValA := StrToIntDef(grid.Cells[ACol, ARow], 0);
    ValB := StrToIntDef(grid.Cells[BCol, BRow], 0);
    if ValA < ValB then
      Result := -1
    else if ValA > ValB then
      Result := 1
    else
      Result := 0;
  end
  else
  begin
    Result := CompareText(grid.Cells[ACol, ARow], grid.Cells[BCol, BRow]);
  end;
  
  if grid.SortOrder = soDescending then
    Result := -Result;
end;

procedure TfrmMain.gridDblClick(Sender : TObject);
begin
  OpenDisassemblyView;
end;

procedure TfrmMain.OpenDisassemblyView;
var
  r: Integer;
  VMA: string;
  Size: Integer;
  ElfFile: string;
begin
  r := grid.Row;
  if r < 1 then Exit;

  VMA := grid.Cells[vma_col_idx, r];
  Size := StrToIntDef(grid.Cells[size_col_idx, r], 0);

  if (VMA = '') or (Size <= 0) then
  begin
    ShowMessage('Invalid VMA or Size for disassembly.');
    Exit;
  end;

  ElfFile := ChangeFileExt(mapfile.filename, '.elf');
  if not FileExists(ElfFile) then
    ElfFile := ChangeFileExt(mapfile.filename, '.axf');

  if not FileExists(ElfFile) then
  begin
    ShowMessage('Could not find corresponding .elf or .axf file in the same directory as the map file.');
    Exit;
  end;

  ShowDisassembly(ElfFile, VMA, Size);
end;


procedure TfrmMain.gridHeaderClick(Sender: TObject; IsColumn: Boolean;
  Index: Integer);
begin
  if not IsColumn then Exit;
  
  if FLastSortCol = Index then
    FSortAscending := not FSortAscending
  else
  begin
    FLastSortCol := Index;
    FSortAscending := True; // normally True is descending for size? No, keep it standard
  end;
  
  if FSortAscending then
    grid.SortOrder := soAscending
  else
    grid.SortOrder := soDescending;
    
  grid.SortColRow(True, Index);
end;

procedure TfrmMain.UpdateSelectedSize;
var
  r, i: Integer;
  Sum: Int64;
  Rng: TGridRect;
  IsSel: Boolean;
begin
  Sum := 0;
  for r := 1 to grid.RowCount - 1 do
  begin
    IsSel := False;
    
    if grid.SelectedRangeCount > 0 then
    begin
      for i := 0 to grid.SelectedRangeCount - 1 do
      begin
        Rng := grid.SelectedRange[i];
        if (r >= Rng.Top) and (r <= Rng.Bottom) then
        begin
          IsSel := True;
          Break;
        end;
      end;
    end
    else
    begin
      if (r >= grid.Selection.Top) and (r <= grid.Selection.Bottom) then
        IsSel := True;
    end;
    
    if IsSel then
      Sum := Sum + StrToInt64Def(grid.Cells[size_col_idx, r], 0);
  end;
  
  txtSelectedSize.Caption := IntToStr(Sum);
end;

procedure TfrmMain.gridSelection(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateSelectedSize;
end;

end.

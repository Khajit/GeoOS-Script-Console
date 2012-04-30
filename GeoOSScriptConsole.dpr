program GeoOSScriptConsole;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  SysUtils,     //basic utils
  Classes,      //some useful classes
  Registry,     //implement Windows registry
  Windows,      //declaration and etc., useful for us
  IdHTTP,       //indy http library for download
  IdAntiFreeze; //indy antifreeze library for stop freezen application, when downloading

var
  paramsraw: string;                   // implement variables for recognition of
  params: TStringList;                 // program parameters (max up to 50 params)
  CommandSplit1: TStringList;          // for spliting of commands (main - what is command, and what are parameters)
  CommandSplit2: TStringList;          // for spliting of commands (minor - if multiple parameters, split them too)
  reg: TRegistry;                      // variable for accessing Windows registry
  fIDHTTP: TIdHTTP;                    // variable for downloading
  antifreeze: TIdAntiFreeze;           // variable for stopping freezing application, when download

function DownloadFile( const aSourceURL: String;
                   const aDestFileName: String): boolean;
var
  Stream: TMemoryStream;
begin
  Result := FALSE;
  fIDHTTP := TIDHTTP.Create;
  fIDHTTP.HandleRedirects := TRUE;
  fIDHTTP.AllowCookies := FALSE;
  fIDHTTP.Request.UserAgent := 'Mozilla/4.0';
  fIDHTTP.Request.Connection := 'Keep-Alive';
  fIDHTTP.Request.ProxyConnection := 'Keep-Alive';
  fIDHTTP.Request.CacheControl := 'no-cache';
  //fIDHTTP.OnWork:=IdHTTPWork;
  //fIDHTTP.OnWorkBegin:=IdHTTPWorkBegin;           //this will be for download status -> not needed now
  //fIDHTTP.OnWorkend:=IdHTTPWorkEnd;

  Stream := TMemoryStream.Create;
  try
    try
      fIDHTTP.Get(aSourceURL, Stream);
      if FileExists(aDestFileName) then
        DeleteFile(PWideChar(aDestFileName));
      Stream.SaveToFile(aDestFileName);
      Result := TRUE;
    except
      On E: Exception do
        begin
          Result := FALSE;
        end;
    end;
  finally
    Stream.Free;
    fIDHTTP.Free;
  end;
end;

procedure Split(Delimiter: Char; Str: string; ListOfStrings: TStrings); // Split what we need
//thanks to RRUZ - http://stackoverflow.com/questions/2625707/delphi-how-do-i-split-a-string-into-an-array-of-strings-based-on-a-delimiter
begin
   ListOfStrings.Clear;
   ListOfStrings.Delimiter     := Delimiter;
   ListOfStrings.DelimitedText := Str;
end;

function GetParams(): string; //gets all parameters
var
  returnstr: string;
  i: integer;
begin
returnstr:='';
for i:=1 to ParamCount() do
begin
  returnstr:=returnstr+ParamStr(i)+'|';
end;
result:=returnstr;
end;

function LookUpForParams(): string; //Search, how many and what parameters are used
begin
if(ParamCount()>0) then
begin
  result:=GetParams();
end;
end;

function SearchForSplitParam(param: string): boolean;
var index: integer;
begin
  index:=-1;  //because index cannot be negative
  index:=params.IndexOf(param);
  if not(index=-1) then //if index of given searched string isn't found, value of 'index' is still -1 (not found)
  begin
    result:=true; //param is found
  end
  else
  begin
    result:=false; //param is not found
  end;
end;

function GetInitIndex(param: char): integer; //gets index of -i or -i parameters (of ParamStrs)
var index: integer;
begin
  index:=-1;  //because index cannot be negative
  index:=params.IndexOf('-'+param);
  //we know, that it already exists, so there is no condition for: if index is not -1
  result:=index;
end;

function IsRemote(param: string): boolean; //Local -> false | Remote -> true
var
  split1: string;
  split2: string;
  split3: string;
begin
  split1:=param[1]+param[2]+param[3]+param[4]+param[5]+param[6]+param[7];
  split2:=param[1]+param[2]+param[3]+param[4]+param[5]+param[6]+param[7]+param[8];
  split3:=param[1]+param[2]+param[3]+param[4]+param[5]+param[6];
  if(split1='http://') then result:=true        //accepting http:// as remote
  else if(split2='https://') then result:=true  //accepting https:// as remote
  else if(split3='ftp://') then result:=true    //accepting ftp:// as remote
  else result:=false; //everything else is in local computer
end;

function empty(str: string): boolean;
begin
  if(str='') then result:=true
  else result:=false;
end;

function GetLocalDir(): string;
begin
  result:=ExtractFilePath(ParamStr(0));
end;

function GetLocalPath(): string;
begin
  result:=ExtractFilePath(ParamStr(0));
end;

function ReadCommand(str: string): string;
begin
Split('=',str,CommandSplit1);
result:=CommandSplit1[0];
end;

function CommandParams(str: string): string; overload;
begin
Split(',',str,CommandSplit2);
result:=CommandSplit2.Text;
end;

function CommandParams(str: string; index: integer): string; overload;
begin
Split(',',str,CommandSplit2);
result:=CommandSplit2[index];
end;

function RemoveAndReg(reg_loc: string): boolean; overload;
var
  i: integer;
  CommandSplit3: TStringList;
begin
  CommandSplit3.Create();
  reg.OpenKey(reg_loc,false);
  Split('|',reg.ReadString('Sum'),CommandSplit3);

  CommandSplit3.Free;
end;

function Install(path: string): boolean; overload;
var
  f: Text;
  line: string;
begin
  Assign(f,path);
  reset(f);
  readln(f,line);
  if(ReadCommand(line)='ScriptName') then
  begin
    if(reg.KeyExists('Software\GeoOS-Script\'+ReadCommand(line))) then //if exists -> update
    begin
      RemoveAndReg('Software\GeoOS-Script\'+ReadCommand(line)); //delete previosly version
    end;
    repeat
      readln(f,line);

    until EOF(f);
  end
  else
  begin
    writeln('Invalid Script Name!');
  end;
  close(f);
end;

function Install(path: string; temp: boolean): boolean; overload; // determinates, if installing script is in 'temporary' mode
var
  f: Text;
  line: string;
begin
  if(temp=true) then //if not, its normal install
  begin
    Assign(f,path);
    reset(f);
    readln(f,line);
    close(f);
    if(ReadCommand(line)='ScriptName') then
    begin
      CopyFile(PWChar(path),PWChar(GetLocalDir+CommandParams(line)),false);
      Install(GetLocalDir+CommandParams(line));
    end
    else
    begin
      writeln('Invalid script!');
      readln;
    end;
  end
  else
  begin
    Install(path);
  end;
end;

function Remove(path: string): boolean; overload;
var
  f: Text;
  line: string;
begin
  Assign(f,path);
  reset(f);
  repeat
    readln(f,line);
    writeln(line);
  until EOF(f);
  close(f);
end;

function Remove(path: string; temp: boolean): boolean; overload; // determinates, if removing script is in 'temporary' mode
var
  f: Text;
  line: string;
begin
  if(temp=true) then //if not, its normal remove
  begin
    Assign(f,path);
    reset(f);
    readln(f,line);
    close(f);
    if(ReadCommand(line)='ScriptName') then
    begin
      CopyFile(PWChar(path),PWChar(GetLocalDir+CommandParams(line)),false);
      Remove(GetLocalDir+CommandParams(line));
    end
    else
    begin
      writeln('Invalid script!');
      readln;
    end;
  end
  else
  begin
    Remove(path);
  end;
end;

function init(): boolean;
begin
  paramsraw:='';
  params:=TStringList.Create();
  CommandSplit1:=TStringList.Create();
  CommandSplit2:=TStringList.Create();
  paramsraw:=LookUpForParams(); //Main initializon for parameters... what to do and everything else
  if(empty(paramsraw)) then //If program didn't find any parameters
  begin
    write('No parameters detected, write one now: ');
    read(paramsraw);
    readln;
    paramsraw:=StringReplace(paramsraw,' ','|',[rfReplaceAll, rfIgnoreCase]);
  end;
  Split('|',paramsraw,params); //Get every used param
  // initialize registry variable
  reg:=TRegistry.Create();
  reg.RootKey:=HKEY_CURRENT_USER;
  if(reg.KeyExists('Software\GeoOS-Script\')) then
  begin
    reg.OpenKey('Software\GeoOS-Script\',false);
  end
  else
  begin
    reg.CreateKey('Software\GeoOS-Script\');
    reg.OpenKey('Software\GeoOS-Script\',false);
  end;
  // end of inicializing of registry variable
  // initialize indys
  fIDHTTP:=TIdHTTP.Create();
  antifreeze:=TIdAntiFreeze.Create();
end;

function FreeAll(): boolean;
begin
  reg.Free;           //release memory from using registry variable
  params.Free;        //release memory from using stringlist variable
  CommandSplit1.Free; //release memory from using main split
  CommandSplit2.Free; //release memory from using minor split
  //indy http lybrary is freed on every use of DownloadFile();
  antifreeze.Free;
end;

begin
  writeln('Starting...'); // Starting of script
  // initialize needed variables
  init();
  // Now we need if it would be an install (or update) or uninstall (remove or downgrade)
  if(SearchForSplitParam('-i') and not(SearchForSplitParam('-r'))) then
  begin
    //Install script or update (-i means install)
    //If -r (-r means remove) is found too, params are incorrect
    if(IsRemote(params[GetInitIndex('i')+1])) then
    begin
      //initialize download -not fully implemented
      DownloadFile(params[GetInitIndex('i')+1],GetLocalDir+'tmpscript.gos');
      if(FileExists(GetLocalDir+'tmpscript.gos')) then
      begin
        writeln('Script downloaded!');
        Install(GetLocalDir+'tmpscript.gos',true);
      end
      else
      begin
        writeln('Script not found!');
      end;
    end
    else // parameter after -i is local? check it
    begin
      if(FileExists(params[GetInitIndex('i')+1])) then
      begin
        //file exists in computer
        Install(params[GetInitIndex('i')+1]);
      end
      else if(FileExists(GetLocalDir+ParamStr(GetInitIndex('i')+1))) then
      begin
        //file exists in local directory
        Install(GetLocalDir+params[GetInitIndex('i')+1]);
      end
      else
      begin
        //local file not found, parameter for file is incorrect
        writeln('Parameters are incorrect! Not found proper .gos link!');
        readln;
        exit; //terminate program
      end;
    end;
  end
  else if(SearchForSplitParam('-r') and not(SearchForSplitParam('-i'))) then
  begin
    //Remove script or downgrade (-r means remove)
    //If -i (-i means install) is found too, params are incorrect
    if(IsRemote(params[GetInitIndex('r')+1])) then
    begin
      //initialize download -not fully implemented
      DownloadFile(params[GetInitIndex('r')+1],GetLocalDir+'tmpscript.gos');
      if(FileExists(GetLocalDir+'tmpscript.gos')) then
      begin
        writeln('Script downloaded!');
        Remove(GetLocalDir+'tmpscript.gos',true);
      end
      else
      begin
        writeln('Script not found!');
      end;
    end
    else // parameter after -i is local? check it
    begin
      if(FileExists(params[GetInitIndex('r')+1])) then
      begin
        //file exists in computer
        Remove(params[GetInitIndex('r')+1]);
      end
      else if(FileExists(GetLocalDir+ParamStr(GetInitIndex('r')+1))) then
      begin
        //file exists in local directory
        Remove(GetLocalDir+params[GetInitIndex('r')+1]);
      end
      else
      begin
        //local file not found, parameter for file is incorrect
        writeln('Parameters are incorrect! Not found proper .gos link!');
        readln;
        exit; //terminate program
      end;
    end;
  end
  else if(SearchForSplitParam('-i') and SearchForSplitParam('-r')) then
  begin
    writeln('Parameters are incorrect! Found both -i and -r!');
    readln;
    exit; //terminate program
  end
  else
  begin
    writeln('Parameters are incorrect! Parameters -i or -r weren�t recognized!');
    readln;
    exit; //terminate program
  end;
  FreeAll();
  // THE END
  readln;
end.
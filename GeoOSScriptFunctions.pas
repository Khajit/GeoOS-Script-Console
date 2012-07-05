unit GeoOSScriptFunctions;
{
  Version 0.24
  Copyright 2012 Geodar
  https://github.com/Geodar/GeoOS_Script_Functions
}
interface
  uses
    Windows, SysUtils, Classes, shellapi, Zip, StrUtils
    {$IFDEF CONSOLE}, WinINet
    {$ELSE}, Dialogs, IdHTTP, IdAntiFreeze, IdComponent, Forms{$ENDIF};

  type TWinVersion = (wvUnknown, wvWin95, wvWin98, wvWin98SE, wvWinNT, wvWinME, wvWin2000, wvWinXP, wvWinVista);

  type functions = record
    public
    function GetWinVersion: TWinVersion; stdcall;
    function FreeAll(): boolean; stdcall;
    function DownloadFile(const url: string; const destinationFileName: string): boolean; stdcall;
    function GetParams(): string; stdcall;
    function LookUpForParams(): string; stdcall;
    function ReadCommand(str: string): string; stdcall;
    function CommandParams(str: string): string; overload; stdcall;
    function CommandParams(str: string; index: integer): string; overload; stdcall;
    function CommandParams(str: string; index: integer; commandindex: integer): string; overload; stdcall;
    function CheckDirAndDownloadFile(url: string; path: string): boolean; stdcall;
    function ReadAndDoCommands(line: string): boolean; stdcall;
    function TerminateMe(): boolean; stdcall;
    function LogAdd(messages: string): TStringList; stdcall;
    function ShowLog(): TStringList; stdcall;
    function init(): boolean; stdcall;
    function empty(str: string): boolean; stdcall;
    function GetLocalDir(): string; stdcall;
    function GetLocalPath(): string; stdcall;
    function CheckVersionInOnlineStore(programname: string; currversion: real): real; stdcall;
    procedure Split(Delimiter: Char; Str: string; ListOfStrings: TStrings);
  end;

  var
    ZipHandler:                      TZipFile;  // for accessing zip files
    CommandSplit1:                TStringList;  // for spliting of commands (main - what is command, and what are parameters)
    CommandSplit2:                TStringList;  // for spliting of commands (minor - if multiple parameters, split them too)
    Handle:                              HWND;  // some handle variable for shellapi
    _log:                         TStringList;  // holds information about scripts progress
    {$IFNDEF CONSOLE}
    fIDHTTP:          array [1..5] of TIDHTTP;  // max support for 5 downloads at time
    Stream:     array [1..5] of TMemoryStream;  // downloading streams
    idAntiFreeze:               TIdAntiFreeze;  // stop freezing application while downloading a file
    {$ENDIF}

implementation

{$IFNDEF CONSOLE}
uses Unit1;
{$ENDIF}

procedure functions.Split(Delimiter: Char; Str: string; ListOfStrings: TStrings); // Split what we need
//thanks to RRUZ - http://stackoverflow.com/questions/2625707/delphi-how-do-i-split-a-string-into-an-array-of-strings-based-on-a-delimiter
begin
  ListOfStrings.Clear;
  ListOfStrings.Delimiter     := Delimiter;
  ListOfStrings.DelimitedText := Str;
end;

function functions.empty(str: string): boolean;
begin
  if(Length(str)=0) then result:=true
  else result:=false;
end;

function functions.GetLocalDir(): string;   //same function as GetLocalPath()
begin
  result:=ExtractFilePath(ParamStr(0));
end;

function functions.GetLocalPath(): string; //same function as GetLocalDir()
begin
  result:=ExtractFilePath(ParamStr(0));
end;

function functions.GetWinVersion: TWinVersion; //taken from GeoOS_Main.exe
 var
    osVerInfo: TOSVersionInfo;
    majorVersion, minorVersion: Integer;
 begin
    Result := wvUnknown;
    osVerInfo.dwOSVersionInfoSize := SizeOf(TOSVersionInfo) ;
    if GetVersionEx(osVerInfo) then
    begin
      minorVersion := osVerInfo.dwMinorVersion;
      majorVersion := osVerInfo.dwMajorVersion;
      case osVerInfo.dwPlatformId of
        VER_PLATFORM_WIN32_NT:
        begin
          if majorVersion <= 4 then
            Result := wvWinNT
          else if (majorVersion = 5) and (minorVersion = 0) then
            Result := wvWin2000
          else if (majorVersion = 5) and (minorVersion = 1) then
            Result := wvWinXP
          else if (majorVersion = 6) then
            Result := wvWinVista;
        end;
        VER_PLATFORM_WIN32_WINDOWS:
        begin
          if (majorVersion = 4) and (minorVersion = 0) then
            Result := wvWin95
          else if (majorVersion = 4) and (minorVersion = 10) then
          begin
            if osVerInfo.szCSDVersion[1] = 'A' then
              Result := wvWin98SE
            else
              Result := wvWin98;
          end
          else if (majorVersion = 4) and (minorVersion = 90) then
            Result := wvWinME
          else
            Result := wvUnknown;
        end;
      end;
    end;
 end;

function functions.FreeAll(): boolean;
begin
  CommandSplit1.Free;   //release memory from using main split
  CommandSplit2.Free;   //release memory from using minor split
  ZipHandler.Free;      //release memory from using zip handler
  _log.Free;            //release memory from logs
  {$IFNDEF CONSOLE}
  idAntiFreeze.Free;
  {$ENDIF}
  result:=true;
end;

{$IFDEF CONSOLE}
function functions.DownloadFile(const url: string; const destinationFileName: string): boolean;
var
  hInet: HINTERNET;
  hFile: HINTERNET;
  localFile: File;
  buffer: array[1..1024] of byte;
  bytesRead: DWORD;
begin
  result:=False;
  hInet:=InternetOpen(PChar('GeoOSScript Mozilla/4.0'),INTERNET_OPEN_TYPE_DIRECT,nil,nil,0);
  hFile:=InternetOpenURL(hInet,PChar(url),nil,0,INTERNET_FLAG_NO_CACHE_WRITE+INTERNET_FLAG_ASYNC+INTERNET_FLAG_RELOAD,0);
  if(FileExists(destinationFileName)) then
  begin
    DeleteFile(PWChar(destinationFileName));
  end;
  if Assigned(hFile) then
  begin
    AssignFile(localFile,destinationFileName);
    Rewrite(localFile,1);
    repeat
      InternetReadFile(hFile,@buffer,SizeOf(buffer),bytesRead);
      BlockWrite(localFile,buffer,bytesRead);
    until bytesRead = 0;
    CloseFile(localFile);
    result:=true;
    InternetCloseHandle(hFile);
  end;
  InternetCloseHandle(hInet);
end;
{$ELSE}

function GetDLFreeSlot(): smallint;
var i: smallint;
begin
  result:=0;
  for i:=5 downto 1 do
  begin
    if not(Assigned(fIDHTTP[i])) then
    begin
      result:=i;
    end;
  end;
end;

function functions.DownloadFile(const url: string; const destinationFileName: string): boolean;
var
  availabledl: smallint;
begin
  result := FALSE;
  availabledl:=GetDLFreeSlot();
  if not(availabledl=0) then
  begin
    fIDHTTP[availabledl]:=TIDHTTP.Create();
    fIDHTTP[availabledl].HandleRedirects:=TRUE;
    fIDHTTP[availabledl].AllowCookies:=FALSE;
    fIDHTTP[availabledl].Request.UserAgent:='GeoOSScript Mozilla/4.0';
    fIDHTTP[availabledl].Request.Connection:='Keep-Alive';
    fIDHTTP[availabledl].Request.ProxyConnection:='Keep-Alive';
    fIDHTTP[availabledl].Request.CacheControl:='no-cache';

    Stream[availabledl] := TMemoryStream.Create;
    try
      fIDHTTP[availabledl].Head(url);
      if(fIDHTTP[availabledl].Response.ResponseCode=200) then
      begin
        fIDHTTP[availabledl].Get(url, Stream[availabledl]);
        if FileExists(destinationFileName) then
          DeleteFile(PWideChar(destinationFileName));
        Stream[availabledl].SaveToFile(destinationFileName);
        result := TRUE;
      end;
    finally
      FreeAndNil(Stream[availabledl]);
      FreeAndNil(fIDHTTP[availabledl]);
    end;
  end;
end;
{$ENDIF}

function functions.GetParams(): string; //gets all parameters
var
  returnstr: string;
  i: integer;
begin
  returnstr:='';
  if(ParamCount()>0) then
    for i:=1 to ParamCount() do
      returnstr:=returnstr+ParamStr(i)+'|';
  result:=returnstr;
end;

function functions.LookUpForParams(): string; //Search, how many and what parameters are used
begin
  if(ParamCount()>0) then
    result:=GetParams()
  else
    result:='';
end;

function functions.ReadCommand(str: string): string;
begin
  Split('=',str,CommandSplit1);
  if not(CommandSplit1.Count=0) then
    result:=CommandSplit1.Strings[0]
  else
    result:='';
end;

function functions.CommandParams(str: string): string;
begin
  Split('=',str,CommandSplit1);
  if not(CommandSplit1.Count=1) then
    result:=CommandSplit1.Strings[1]
  else
    result:='';
end;

function functions.CommandParams(str: string; index: integer): string;
begin
  Split('=',str,CommandSplit1);
  Split(',',CommandSplit1[1],CommandSplit2);
  if((CommandSplit2.Count-1)>=index) then
    result:=CommandSplit2.Strings[index]
  else
    result:='';
end;

function functions.CommandParams(str: string; index: integer; commandindex: integer): string;
begin
  Split('=',str,CommandSplit1);
  Split(',',CommandSplit1[commandindex+1],CommandSplit2);
  if((CommandSplit2.Count-1)>=index) then
    result:=CommandSplit2.Strings[index]
  else
    result:='';
end;

function functions.CheckVersionInOnlineStore(programname: string; currversion: real): real;
var
  fFile: Text;
  line: string;
begin
  result:=0.0;
  DownloadFile('http://geodar.hys.cz/geoos/'+programname+'.gos',GetLocalDir()+programname+'.gos');
  if(FileExists(GetLocalDir()+programname+'.gos')) then
  begin
    Assign(fFile,GetLocalDir()+programname+'.gos');
    reset(fFile);
    repeat
      readln(fFile,line);
      if(ReadCommand(line)='Version') then
        if(StrToFloat(CommandParams(line))>currversion) then
          result:=StrToFloat(CommandParams(line));
    until EOF(fFile) or not(result=0);
    Close(fFile);
  end;
end;

function functions.CheckDirAndDownloadFile(url: string; path: string): boolean;
var
  splitdir:  TStringList;
  splitdir2: TStringList;
  i:             integer;
  str:            string;
  hope:          boolean;
begin
  splitdir:=TStringList.Create();
  splitdir2:=TStringList.Create();
  str:=ExtractFileDir(ParamStr(0));
  hope:=false;
  Split('\',path,splitdir);
  Split('/',path,splitdir2);
  if(splitdir.Count>1) then //if \ is used for specified directory
  begin
    hope:=true;
    for i:=0 to splitdir.Count-2 do //make directory for each one of them
    begin
      str:=str+'\'+splitdir[i];
      if not(DirectoryExists(str)) then
        MkDir(str);
    end;
  end;
  if((splitdir2.Count>1) and not(hope)) then // / is used for specified directory
  begin
    for i:=0 to splitdir2.Count-2 do //make directory for each one of them
    begin
      str:=str+'\'+splitdir2[i];
      if not(DirectoryExists(str)) then
        MkDir(str);
    end;
  end;
  splitdir.Free;
  splitdir2.Free;
  result:=DownloadFile(url,GetLocalPath()+path);
end;

function functions.TerminateMe(): boolean;
begin
  FreeAll();
  {$IFDEF CONSOLE}
  Halt(0); //terminate console
  {$ELSE}
  Application.Terminate; //terminate form program
  {$ENDIF}
  result:=true;
end;

function functions.ReadAndDoCommands(line: string): boolean; //the most important function!
var
  comm,par: string;
  yn: string;
begin
  comm:=ReadCommand(line);
  par:=CommandParams(line);
  result:=true;
  {$IFNDEF CONSOLE}
  Handle:=Application.Handle;
  {$ENDIF}
  if(empty(comm)) then // if command is missing, don't do anything
  begin
    LogAdd('Command whitespace');
    result:=false;
  end
  else if((comm='CloseMe') or (comm='TerminateMe')) then
  begin
    TerminateMe();
    result:=true;
  end
  else if(empty(par)) then // if parameter is missing, don't do anything
  begin
    LogAdd('Parameter whitespace');
    result:=false;
  end
  else if(comm='ScriptName') then
    LogAdd('Script name: '+par)
  else if(comm='Author') then //Write script's author
    LogAdd('Script�s Author: '+par)
  else if(comm='Log') then //Write a message
    LogAdd(StringReplace(par,'_',' ', [rfReplaceAll, rfIgnoreCase]))
  {$IFDEF CONSOLE}
  else if(comm='LogEnter') then //Write a message, user need to hit enter to continue with program
  begin
    write(StringReplace(par,'_',' ', [rfReplaceAll, rfIgnoreCase]));
    readln;
  end
  {$ENDIF}
  else if(comm='Version') then //Write a message
    LogAdd('Script Version: '+par)
  else if(comm='PromptYesNo') then //Ask user to do some command, if 'y' is prompt that command will be used
  begin
    {$IFDEF CONSOLE}
    write(StringReplace(CommandParams(line,0),'_',' ', [rfReplaceAll, rfIgnoreCase])+' [y/n]: ');
    read(yn);
    readln;
    {$ELSE}
    yn:=InputBox('GeoOS Script',StringReplace(CommandParams(line,0),'_',' ', [rfReplaceAll, rfIgnoreCase])+' [y/n]: ','n');
    {$ENDIF}
    SetLength(yn,1);
    if(yn='y') then
    begin
      if not(empty(CommandParams(line,1,1))) then //support for Execute
      begin
        LogAdd('You prompt: '+CommandParams(line,1)+'='+CommandParams(line,0,1)+','+CommandParams(line,1,1));
        ReadAndDoCommands(CommandParams(line,1)+'='+CommandParams(line,0,1)+','+CommandParams(line,1,1));
      end
      else
      begin
        LogAdd('You prompt: '+CommandParams(line,1)+'='+CommandParams(line,0,1));
        ReadAndDoCommands(CommandParams(line,1)+'='+CommandParams(line,0,1));
      end;
    end
    else
      LogAdd('Prompt: Do Nothing');
  end
  else if(comm='MkDir') then //Create Directory
  begin
    if not(DirectoryExists(GetLocalDir()+par)) then
    begin
      mkdir(GetLocalDir()+par);
      LogAdd('Directory "'+GetLocalDir()+par+'" created.');
    end;
  end
  else if(comm='RmDir') then //Remove Directory
  begin
    if(DirectoryExists(GetLocalDir()+par)) then
    begin
      rmdir(GetLocalDir()+par);
      LogAdd('Directory "'+GetLocalDir()+par+'" removed.');
    end;
  end
  else if(comm='RmFile') then //Remove File
  begin
    if(FileExists(GetLocalDir()+par)) then
    begin
      deletefile(PWChar(GetLocalDir()+par));
      LogAdd('File "'+GetLocalDir()+par+'" removed.');
    end;
  end
  else if(comm='CopyFile') then //Copy File
  begin
    if(FileExists(GetLocalDir()+CommandParams(line,0))) then
    begin
      if(FileExists(GetLocalDir()+CommandParams(line,1))) then
      begin
        if(CommandParams(line,2)='overwrite') then
        begin
          CopyFile(PWChar(GetLocalDir()+CommandParams(line,0)),PWChar(GetLocalDir()+CommandParams(line,1)),false);
          LogAdd('File "'+GetLocalDir()+CommandParams(line,0)+'" copied to "'+GetLocalDir()+CommandParams(line,1)+'". autooverwrite');
        end
        else
        begin
          {$IFDEF CONSOLE}
          write('File "'+GetLocalDir()+CommandParams(line,1)+'" already exists, overwrite? [y/n]: ');
          read(yn);
          readln;
          {$ELSE}
          yn:=InputBox('GeoOS Script','File "'+CommandParams(line,1)+'" already exists, overwrite? [y/n]: ','n');
          {$ENDIF}
          SetLength(yn,1);
          if(yn='y') then // if user type "y" it means "yes"
          begin
            CopyFile(PWChar(GetLocalDir()+CommandParams(line,0)),PWChar(GetLocalDir()+CommandParams(line,1)),false);
            LogAdd('File "'+GetLocalDir()+CommandParams(line,0)+'" copied to "'+GetLocalDir()+CommandParams(line,1)+'".');
          end
          else
            LogAdd('OK');
        end;
      end
      else
      begin
        CopyFile(PWChar(GetLocalDir()+CommandParams(line,0)),PWChar(GetLocalDir()+CommandParams(line,1)),false);
        LogAdd('File "'+GetLocalDir()+CommandParams(line,0)+'" copied to "'+GetLocalDir()+CommandParams(line,1)+'".');
      end;
    end
    else
      LogAdd('File "'+GetLocalDir()+CommandParams(line,0)+'" copied to "'+GetLocalDir()+CommandParams(line,1)+'" failed! File "'+CommandParams(line,0)+'" doesn�t exists!');
  end
  else if(comm='Execute') then
  begin
    if(FileExists(GetLocalDir()+CommandParams(line,0))) then
    begin
      if(GetWinVersion=wvWinVista) then
      begin
        ShellExecute(Handle,'runas',PWChar(GetLocalDir()+CommandParams(line,0)),PWChar(StringReplace(CommandParams(line,1),'_',' ', [rfReplaceAll, rfIgnoreCase])),PWChar(GetLocalDir),1);
        LogAdd('File "'+CommandParams(line,0)+'" executed as admin with "'+StringReplace(CommandParams(line,1),'_',' ', [rfReplaceAll, rfIgnoreCase])+'" parameters.');
      end
      else
      begin
        ShellExecute(Handle,'open',PWChar(GetLocalDir()+CommandParams(line,0)),PWChar(StringReplace(CommandParams(line,1),'_',' ', [rfReplaceAll, rfIgnoreCase])),PWChar(GetLocalDir),1);
        LogAdd('File "'+CommandParams(line,0)+'" executed with "'+StringReplace(CommandParams(line,1),'_',' ', [rfReplaceAll, rfIgnoreCase])+'" parameters.');
      end;
    end
    else
      LogAdd('File "'+CommandParams(line,0)+'" doesn�t exists!');
  end
  else if(comm='DownloadFile') then
  begin
    if(fileexists(GetLocalDir()+CommandParams(line,1))) then
    begin
      if(CommandParams(line,2)='overwrite') then
      begin
        LogAdd('Downloading "'+CommandParams(line,0)+'" to "'+GetLocalDir()+CommandParams(line,1)+'" ... autooverwrite');
        result:=CheckDirAndDownloadFile(CommandParams(line,0),CommandParams(line,1));
      end
      else
      begin
        {$IFDEF CONSOLE}
        write('File "',GetLocalDir()+CommandParams(line,1),'" already exists, overwrite? [y/n]: ');
        read(yn);
        readln;
        {$ELSE}
        yn:=InputBox('GeoOS Script','File "'+CommandParams(line,1)+'" already exists, overwrite? [y/n]: ','n');
        {$ENDIF}
        SetLength(yn,1);
        if(yn='y') then // if user type "y" it means "yes"
        begin
          LogAdd('Downloading "'+CommandParams(line,0)+'" to '+GetLocalDir()+CommandParams(line,1)+'" ...');
          result:=CheckDirAndDownloadFile(CommandParams(line,0),CommandParams(line,1));
        end;
      end;
    end
    else  //file does not exists
    begin
      LogAdd('Downloading "'+CommandParams(line,0)+'" to "'+GetLocalDir()+CommandParams(line,1)+'" ...');
      result:=CheckDirAndDownloadFile(CommandParams(line,0),CommandParams(line,1));
    end;
    LogAdd('OK');
  end
  else if(comm='ZipExtract') then
  begin
    if(ZipHandler.IsValid(par)) then
    begin
      ZipHandler.ExtractZipFile(par,GetLocalPath()+'geoos\');
      LogAdd('File "'+par+'" extracted.');
    end
    else
      LogAdd('File "'+par+'" is not valid zip file!');
  end
  else if(comm='ZipExtractTo') then
  begin
    if(ZipHandler.IsValid(CommandParams(line,0))) then
    begin
      ZipHandler.ExtractZipFile(CommandParams(line,0),GetLocalPath()+CommandParams(line,1));
      LogAdd('File "'+CommandParams(line,0)+'" extracted to "'+CommandParams(line,1)+'".');
    end
    else
      LogAdd('File "'+CommandParams(line,0)+'" is not valid zip file!');
  end
  else
  begin
    LogAdd('Command "'+comm+'" not found!');
    result:=false;
  end;
end;

function functions.LogAdd(messages: string): TStringList;
begin
  _log.Add(messages);
  result:=ShowLog();
end;

function functions.ShowLog(): TStringList;
begin
  {$IFDEF CONSOLE}
  writeln(_log.Strings[_log.Count-1]);
  {$ELSE}
  Form1.HandleGeoOSScriptMsg(_log.Strings[_log.Count-1]);
  {$ENDIF}
  result:=_log;
end;

function functions.init(): boolean;
begin
  CommandSplit1:=TStringList.Create();
  CommandSplit2:=TStringList.Create();
  ZipHandler:=TZipFile.Create();
  {$IFNDEF CONSOLE}
  idAntiFreeze:=TIdAntiFreeze.Create();
  {$ENDIF}
  _log:=TStringList.Create();
  _log.Add('GeoOS Script Log Init.');
  result:=true;
end;

end.

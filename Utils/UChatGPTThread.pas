{***************************************************}
{                                                   }
{   This unit contains a worker thread to do        }
{   API calls and some other stuff.                 }
{   Auhtor: Ali Dehbansiahkarbon(adehban@gmail.com) }
{                                                   }
{***************************************************}
unit UChatGPTThread;

interface
uses
  System.Classes, System.SysUtils, IdHTTP, IdSSLOpenSSL, IdComponent, Vcl.Dialogs,
  XSuperObject, System.Generics.Collections, Winapi.Messages, Winapi.Windows,
  UChatGPTSetting, UConsts, System.JSON, System.StrUtils;

type
  TExecutorTrd = class(TThread)
  private
    FHandle: HWND;
    FPrompt: string;
    FMaxToken: Integer;
    FTemperature: Integer;
    FModel: string;
    FApiKey: string;
    FFormattedResponse: TStringList;
    FUrl: string;
    FProxySetting: TProxySetting;
    FAnimated: Boolean;
    FTimeOut: Integer;
    function IsValidJson(const AJsonString: string): Boolean;
    function CorrectPrompt(APrompt: string): string;
  protected
    procedure Execute; override;
  public
    constructor Create(AHandle: HWND; AApiKey, AModel, APrompt, AUrl: string; AMaxToken, ATemperature: Integer;
                       AProxayIsActive: Boolean; AProxyHost: string; AProxyPort: Integer; AProxyUsername: string;
                       AProxyPassword: string; AAnimated: Boolean; ATimeOut: Integer);
    destructor Destroy; override;
  end;

  TRequestJSON = class
  private
    FModel: string;
    FPrompt: string;
    FMax_tokens: Integer;
    FTemperature: Integer;
  public
    property model: string read FModel write FModel;
    property prompt: string read FPrompt write FPrompt;
    property max_tokens: Integer read FMax_tokens write FMax_tokens;
    property temperature: Integer read FTemperature write FTemperature;
  end;

  TChoice = class
  private
    FText: string;
    FIndex: Integer;
    FLogProbs: string;
    FFinish_reason: string;
  published
    property text: string read FText write FText;
    property &index: Integer read FIndex write FIndex;
    property logprobs: string read FLogProbs write FLogProbs;
    property finish_reason: string read FFinish_reason write FFinish_reason;
  end;

  TUsage = class
  private
    FPrompt_Tokens: Integer;
    FCompletion_Tokens: Integer;
    FTotal_Tokens: Integer;
  published
    property prompt_tokens: Integer read FPrompt_Tokens write FPrompt_Tokens;
    property completion_tokens: Integer read FCompletion_Tokens write FCompletion_Tokens;
    property total_tokens: Integer read FTotal_Tokens write FTotal_Tokens;
  end;

  TChatGPTResponse = class
  private
    FId: string;
    FObject: string;
    FCreated: Integer;
    FModel: string;
    FChoices: TObjectList<TChoice>;
    FUsage: TUsage;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property id: string read FId write FId;
    property &object: string read FObject write FObject;
    property created: Integer read FCreated write FCreated;
    property model: string read FModel write FModel;
    property choices: TObjectList<TChoice> read FChoices write FChoices;
    property usage: TUsage read FUsage write FUsage;
  end;
  
  TOpenAIAPI = class
  private
    FAccessToken: string;
    FUrl: string;
    FProxySetting: TProxySetting;
    FTimeOut: Integer;

  public
    constructor Create(const AAccessToken, AUrl: string; AProxySetting: TProxySetting; ATimeOut: Integer);
    function QueryStream(const AModel: string; const APrompt: string; AMaxToken: Integer; Aemperature: Integer): string;
    function QueryString(const AModel, APrompt: string; AMaxToken, ATemperature: Integer): string;
  end;

implementation

{ TOpenAIAPI }
constructor TOpenAIAPI.Create(const AAccessToken, AUrl: string; AProxySetting: TProxySetting; ATimeOut: Integer);
begin
  inherited Create;
  FAccessToken := AAccessToken;
  FUrl := AUrl;
  FProxySetting := AProxySetting;
  FTimeOut := ATimeOut;
end;

function TOpenAIAPI.QueryStream(const AModel: string; const APrompt: string; AMaxToken: Integer; Aemperature: Integer): string;
var
  LvHttpClient: TIdHTTP;
  LvSslIOHandler: TIdSSLIOHandlerSocketOpenSSL;
  LvParamStream: TStringStream;

  LvRequestJSON: TRequestJSON;
  LvChatGPTResponse: TChatGPTResponse;

  LvResponseStream: TStringStream;
begin
  LvHttpClient := TIdHTTP.Create(nil);
  LvHttpClient.ConnectTimeout := FTimeOut * 1000;
  LvHttpClient.ReadTimeout := (FTimeOut * 1000) * 2;

  if (FProxySetting.Active) and (not LvHttpClient.ProxyParams.ProxyServer.IsEmpty) then
  begin  
    LvHttpClient.ProxyParams.ProxyServer := FProxySetting.ProxyHost;
    LvHttpClient.ProxyParams.ProxyPort := FProxySetting.ProxyPort;
    LvHttpClient.ProxyParams.ProxyUsername := FProxySetting.ProxyUsername;
    LvHttpClient.ProxyParams.ProxyPassword := FProxySetting.ProxyPassword;
  end;    
  
  LvSslIOHandler := TIdSSLIOHandlerSocketOpenSSL.Create(nil);
  LvChatGPTResponse := TChatGPTResponse.Create;
  LvRequestJSON := TRequestJSON.Create;

  with LvRequestJSON do
  begin
    model := AModel;
    prompt := APrompt;
    max_tokens := AMaxToken;
    temperature := Aemperature;
  end;

  try
    LvHttpClient.IOHandler := LvSslIOHandler;
    LvSslIOHandler.SSLOptions.SSLVersions := [sslvTLSv1_2];
    LvParamStream := TStringStream.Create(LvRequestJSON.AsJSON(True), TEncoding.UTF8);

    LvHttpClient.Request.CustomHeaders.AddValue('Authorization', 'Bearer '+ FAccessToken);
    LvHttpClient.Request.ContentType := 'application/json';
    LvHttpClient.Request.AcceptEncoding := 'deflate, gzip;q=1.0, *;q=0.5';

    try
      LvResponseStream := TStringStream.Create;
      LvHttpClient.Post(FUrl , LvParamStream, LvResponseStream);

      if not Assigned(LvResponseStream) then
        Result := 'No response from API, try again with another question.'
      else
      begin
        if not LvResponseStream.DataString.IsEmpty then
            Result := UTF8ToString(LvResponseStream.DataString);
      end;
    except on E: Exception do
      Result := E.Message;
    end;
  finally
    LvResponseStream.Free;
    LvRequestJSON.Free;
    LvParamStream.Free;
    LvChatGPTResponse.Free;
    LvSslIOHandler.Free;
    LvHttpClient.Free;
  end;
end;

function TOpenAIAPI.QueryString(const AModel, APrompt: string; AMaxToken, ATemperature: Integer): string;
var
  LvHttpClient: TIdHTTP;
  LvSslIOHandler: TIdSSLIOHandlerSocketOpenSSL;
  LvParamStream: TStringStream;
  LvResponse: string;
  LvRequestJSON: TRequestJSON;
  LvChatGPTResponse: TChatGPTResponse;
begin
  LvChatGPTResponse := TChatGPTResponse.Create;
  LvHttpClient := TIdHTTP.Create(nil);

  try
    LvSslIOHandler := TIdSSLIOHandlerSocketOpenSSL.Create(nil);
    LvHttpClient.IOHandler := LvSslIOHandler;
    LvSslIOHandler.SSLOptions.SSLVersions := [sslvTLSv1_2];
    LvHttpClient.Request.CustomHeaders.AddValue('Authorization', 'Bearer ' + FAccessToken);
    LvHttpClient.Request.ContentType := 'application/json';

    LvRequestJSON := TRequestJSON.Create;
    with LvRequestJSON do
    begin
      Model := AModel;
      Prompt := APrompt;
      Max_tokens := AMaxToken;
      Temperature := ATemperature;
    end;

    LvParamStream := TStringStream.Create(LvRequestJSON.AsJSON(), TEncoding.UTF8);
    try
      LvResponse := LvHttpClient.Post(FUrl, LvParamStream);

      if not LvResponse.IsEmpty then
        Result :=  UTF8ToString(LvChatGPTResponse.FromJSON(LvResponse).Choices[0].Text.Trim);
    except on E: Exception do
      Result := E.Message;
    end;
  finally
    LvRequestJSON.Free;
    LvParamStream.Free;
    LvChatGPTResponse.Free;
    LvSslIOHandler.Free;
    LvHttpClient.Free;
  end;
end;

{ TChatGPTResponse }

constructor TChatGPTResponse.Create;
begin
  inherited Create;
  FChoices := TObjectList<TChoice>.Create;
  FUsage := Tusage.Create;
end;

destructor TChatGPTResponse.Destroy;
begin
  FChoices.Free;
  FUsage.Free;
  inherited;
end;

{ TExecutorTrd }
function TExecutorTrd.CorrectPrompt(APrompt: string): string;
begin
  if not APrompt.IsEmpty then
  begin
    while APrompt[APrompt.Length] = '?' do
    begin
      if APrompt.Length > 1 then
        APrompt := LeftStr(APrompt, APrompt.Length - 1)
      else
        Break;
    end;
  end;
  Result := APrompt;
end;

constructor TExecutorTrd.Create(AHandle: HWND; AApiKey, AModel, APrompt, AUrl: string; AMaxToken, ATemperature: Integer;
                       AProxayIsActive: Boolean; AProxyHost: string; AProxyPort: Integer; AProxyUsername: string;
                       AProxyPassword: string; AAnimated: Boolean; ATimeOut: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FFormattedResponse := TStringList.Create;
  FApiKey := AApiKey;
  FModel := AModel;
  FPrompt := CorrectPrompt(APrompt);
  FMaxToken := AMaxToken;
  FTemperature := ATemperature;
  FHandle := AHandle;
  FUrl := AUrl;
  FAnimated := AAnimated;
  FTimeOut := ATimeOut;
  FProxySetting := TProxySetting.Create;
  with FProxySetting do
  begin
    Active := AProxayIsActive;
    ProxyHost := AProxyHost;
    ProxyPort := AProxyPort;
    ProxyUsername := AProxyUsername;
    ProxyPassword := AProxyPassword;
  end;
  PostMessage(FHandle, WM_PROGRESS_MESSAGE, 1, 0);
end;

destructor TExecutorTrd.Destroy;
begin
  FFormattedResponse.Free;
  FProxySetting.Free;
  PostMessage(FHandle, WM_PROGRESS_MESSAGE, 0, 0);
  inherited;
end;

procedure TExecutorTrd.Execute;
var
  LvAPI: TOpenAIAPI;
  LvResult: string;
  I: Integer;
{=================================================}
{  Lparams meaning:                               }
{  0 = sending whole string in one message        }
{  1 = sending character by character(animated)   }
{  2 = Finished the task.                         }
{  3 = Exceptions.                                }
{=================================================}
begin
  inherited;
  LvAPI := TOpenAIAPI.Create(FApiKey, FUrl, FProxySetting, FTimeOut);
  try
    try
      if not Terminated then
      begin
        LvResult := LvAPI.QueryStream(FModel, FPrompt, FMaxToken, FTemperature).Trim;

        if (not Terminated) and (not IsValidJson(LvResult)) then
          LvResult := LvAPI.QueryString(FModel, FPrompt, FMaxToken, FTemperature).Trim;
      end;

      if (not Terminated) and (not LvResult.IsEmpty) then
      begin
        if FAnimated then
        begin
          for I := 0 to Pred(LvResult.Length) do
          begin
            if not Terminated then
            begin
              Sleep(1);
              if not Terminated then
                SendMessage(FHandle, WM_UPDATE_MESSAGE, Integer(LvResult[I]), 1);
            end;
          end;
          SendMessage(FHandle, WM_UPDATE_MESSAGE, 0, 2);
        end
        else
        begin
          SendMessageW(FHandle, WM_UPDATE_MESSAGE, Integer(LvResult), 0);
          SendMessage(FHandle, WM_UPDATE_MESSAGE, 0, 2);
        end;
      end;
    except on E: Exception do
      begin
        Sleep(10);
        SendMessageW(FHandle, WM_UPDATE_MESSAGE, Integer(E.Message), 3);
        Terminate;
      end;
    end;
  finally
    LvAPI.Free;
  end;
end;

function TExecutorTrd.IsValidJson(const AJsonString: string): Boolean;
var
  jsonObj: TJSONObject;
begin
  Result := False;
  try
    jsonObj := TJSONObject.ParseJSONValue(AJsonString) as TJSONObject;
    Result := Assigned(jsonObj); // If parsing succeeds, JSON is valid
    jsonObj.Free;
  except
    Result := False;
  end;
end;

end.

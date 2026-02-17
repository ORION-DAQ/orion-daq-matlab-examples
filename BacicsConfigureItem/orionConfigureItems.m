
%% Конфигурация элементов через REST API QServer
%
% Скрипт демонстрирует полный цикл взаимодействия с QServer через REST API:
% 1. Получение списка элементов системы.
% 2. Чтение текущих настроек и режимов работы.
% 3. Изменение параметров конфигурации.
% 4. Применение обновлённых настроек к оборудованию.

%% Предварительные требования
%
% Задайте константы, которые остаются неизменными в течение выполнения скрипта.

% Укажите IP‑адрес вашей системы ORION-daq
ip = "169.254.66.83";

% Создайте базовый URL для HTTP‑запросов. 
% По умолчанию REST API использует порт 8080.
url = "http://" + ip + ":8080/";

% Обработка REST API‑запросов может требовать времени,  
% особенно если QServer выполняется аппаратную конфигурацию.  
% Установите достаточный таймаут (время ожидания).
timeout = 120;

%% Настройка HTTP‑опций для REST API
%
% Настройте параметры для HTTP‑запросов GET и PUT для взаимодействия с REST API.

getOptions = weboptions(...
    'MediaType', 'application/json', ...
    'Timeout', timeout, ...
    'RequestMethod', 'get');

putOptions = weboptions(...
    'MediaType', 'application/x-www-form-urlencoded', ...
    'Timeout', timeout, ...
    'RequestMethod', 'put');

%% Инициализация QServer (опционально)
%
% Сбросьте конфигурацию QServer к настройкам по умолчанию для обеспечения единой точки старта.
% Для этого отправьте PUT‑запрос к конечной точке (endpoint) "system/settings/resetToDefaults".
% Примечание: раскомментируйте следующую строку, если требуется сброс конфигурации.
% responseDefaults = webwrite(url + "system/settings/resetToDefaults", putOptions);


%% Получение идентификатора элемента

% Отправьте GET‑запрос к конечной точке "/item/list", чтобы получить полный список элементов системы.
itemList = webread(url + "item/list", getOptions);

% Извлеките ItemId — уникальный идентификатор элемента, необходимый для дальнейших операций с API.
% В данном примере получаем ItemId первого элемента (предполагается, что это контроллер).
controllerId = itemList(1).ItemId;

%% Опрделение состояния элемента

% У каждого элемента есть состояние, например «Отключён» (Disabled) или «Включён» (Enabled).
% Перед внесением каких‑либо изменений в конфигурацию рекомендуется узнать его текщее состояние.
% 
% Получите информацию о текущем состоянии, 
% отправив запрос к конечной точке "item/operationMode" с указанием параметра itemId.


controllerOperationMode = webread(url + "item/operationMode/?itemId=" + controllerId, getOptions);

% Пример вывода:
% controllerOperationMode = 
% 
%   struct with fields:
% 
%                 ItemId: 1
%               ItemName: 'PQ45'
%     ItemNameIdentifier: 30110
%               ItemType: 'Controller'
%     ItemTypeIdentifier: 0
%                   Info: [1×1 struct]
%        SettingsApplied: 1
%               Settings: [1×1 struct]
%
% Структура controllerOperationMode содержит подробную информацию об элементе:
% - ItemId, ItemName, ItemType: базовые идентификаторы и описание элемента.
% - Info: дополнительные сведения (например, серийный номер).
% - SettingsApplied: флаг, указывающий, применены ли текущие настройки к оборудованию (1 — да, 0 — нет).
% - Settings: структура с доступными настройками и их параметрами.


% Пример доступа к дополнительным сведениям:
% controllerOperationMode.Info
%
% ans = 
% 
%   struct with fields:
% 
%      Name: 'SerialNumber'
%     Value: '0524M7903'

% Пример доступа к списку доступных настроек:
% controllerOperationMode.Settings
%
% ans = 
% 
%   struct with fields:
% 
%                Name: 'Operation Mode'
%                Type: 'Enumeration'
%     SupportedValues: [2×1 struct]
%               Value: 1


% Для каждой настройки в поле SupportedValues содержится список допустимых значений (Id и Description).
%
% controllerOperationMode.Settings.SupportedValues
% 
% ans = 
% 
%   2×1 struct array with fields:
% 
%     Id
%     Description
%
%
% controllerOperationMode.Settings.SupportedValues(1)
% controllerOperationMode.Settings.SupportedValues(2)
%
% ans = 
% 
%   struct with fields:
% 
%              Id: 0
%     Description: 'Disabled'
% 
% 
% ans = 
% 
%   struct with fields:
% 
%              Id: 1
%     Description: 'Enabled'

%% Чтение текущих настроек элемента
%
% Получите полную конфигурацию элемента, включая текущий режим работы и доступные настройки.
% Запрос отправляется к конечной точке "item/settings" с указанием параметра itemId.

controllerSettings = webread(url + "item/settings/?itemId=" + controllerId, getOptions);

% controllerSettings = 
% 
%   struct with fields:
% 
%                 ItemId: 1
%               ItemName: 'PQ45'
%     ItemNameIdentifier: 30110
%               ItemType: 'Controller'
%     ItemTypeIdentifier: 0
%                   Info: [1×1 struct]
%          OperationMode: [1×1 struct]
%        SettingsApplied: 1
%               Settings: [2×1 struct]
%
% Структура controllerSettings включает:
% - OperationMode: текущее состояние элемента.
% - Settings: массив структур с настройками, каждая из которых имеет поля:
%   - Name: название параметра (например, «Master Sampling Rate»).
%   - Type: тип параметра (например, Enumeration).
%   - SupportedValues: список допустимых значений для параметра.
%   - Value: текущее значение параметра.

%% Изменение настроек элемента
%
% Обновите значения параметров в структуре controllerSettings, выбрав допустимые значения из SupportedValues.


% 1. Установите основную частоту дискретизации на 204 800 Гц.
% Найдите настройку «Master Sampling Rate» в массиве Settings.
%
% controllerSettings.Settings(1)
% 
% ans = 
% 
%   struct with fields:
% 
%                Name: 'Master Sampling Rate'
%                Type: 'Enumeration'
%     SupportedValues: [7×1 struct]
%               Value: 
% 
%
% controllerSettings.Settings(1).SupportedValues(7)
% 
% ans = 
% 
%   struct with fields:
% 
%              Id: 6
%     Description: '204800 Hz'
%         Numeric: 204800
%          SIUnit: 'Hz'
% 

% Найдите настройку «Master Sampling Rate» в массиве Settings.
samplingRateSetting = controllerSettings.Settings(1);
% Выберите значение с Id = 6 (соответствует 204 800 Гц) из списка SupportedValues.
controllerSettings.Settings(1).Value = samplingRateSetting.SupportedValues(7).Id;

% 2. Установить формат потоковой передачи анлогвых данных  в «Raw» **
%
% controllerSettings.Settings(2)
% 
% ans = 
% 
%   struct with fields:
% 
%                Name: 'Analog Data Streaming Format'
%                Type: 'Enumeration'
%     SupportedValues: [2×1 struct]
%               Value: 
% 
% controllerSettings.Settings(2).SupportedValues(2)
% 
% ans = 
% 
%   struct with fields:
% 
%              Id: 1
%     Description: 'Raw'

% Найдите настройку «Analog Data Streaming Format» в массиве Settings.
dataFormatSetting = controllerSettings.Settings(2);
% Выберите значение с Id = 1 (соответствует «Raw») из списка SupportedValues.
controllerSettings.Settings(2).Value = dataFormatSetting.SupportedValues(2).Id;

%% Отправка обновлённых настроек на QServer
%
% Примените изменённые настройки с помощью PUT‑запроса, преобразовав структуру MATLAB в JSON.

import matlab.net.http.*

% Настройте заголовки HTTP‑запроса.
acceptField = matlab.net.http.field.AcceptField([matlab.net.http.MediaType('text/*'), matlab.net.http.MediaType('application/json')]);
contentTypeField = matlab.net.http.field.ContentTypeField('application/json');
header = [acceptField contentTypeField];

% Настройте параметры HTTP‑соединения.
putOptionsHTTP = matlab.net.http.HTTPOptions('ConnectTimeout', timeout);

% Создайте HTTP‑запрос PUT с обновлёнными настройками.
requestMessage = matlab.net.http.RequestMessage(matlab.net.http.RequestMethod.PUT, header, controllerSettings);


% Отправьте запрос к конечной точке "item/settings" с указанием itemId.
response = requestMessage.send(url + "item/settings/?itemId=" + controllerId, putOptionsHTTP);

% Проверьте ответ сервера на наличие ошибок.
% Важно: QServer отклоняет недопустимые конфигурации.
if (~isempty(response.Body.Data))
    if response.Body.Data.TypeCode == 1
        % Type = 1, Info message:
        warning(response.Body.Data.Message)
    end
    if response.Body.Data.TypeCode == 2
        % Type = 2, Error message:
        error(response.Body.Data.Message)
    end
end

%% Применение настроек к оборудованию
%
% Синхронизируйте кэшированные настройки с оборудованием, отправив запрос к конечной точке "system/settings/apply".
% Важно: действие «Apply» выполняется один раз после установки всех желаемых параметров для всех элементов.

% Создайте HTTP‑запрос PUT
requestMessageA = matlab.net.http.RequestMessage(matlab.net.http.RequestMethod.PUT,[],struct());

% Отправьте запрос к конечной точке "system/settings/apply"
response = requestMessage.send(url + "system/settings/apply", putOptionsHTTP);

% Проверьте ответ сервера после применения настроек.
if (~isempty(response.Body.Data))
    if response.Body.Data.TypeCode == 1
        % Type = 1, Info message:
        warning(response.Body.Data.Message)
    end
    if response.Body.Data.TypeCode == 2
        % Type = 2, Error message:
        error(response.Body.Data.Message)
    end
end

% После успешного выполнения запроса «Apply» новые настройки будут синхронизированы с оборудованием.


%% Дополнительная информация
%
% Подробную информацию о параметрах настройки и конфигурациях
% см. в руководстве пользователя QServer.
%
% Дополнительные примеры и документацию
% можно найти в репозиториях ORION-DAQ: % https://github.com/ORION-DAQ
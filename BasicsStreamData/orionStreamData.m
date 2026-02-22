%% Потоковая передача данных из QServer
%
% Этот скрипт демонстрирует полный процесс получения данных от QServer:
% 1. Настройка соединения и базовых параметров.
% 2. Поиск активного канала с включённой потоковой передачей.
% 3. Установление TCP‑соединения для приёма данных.
% 4. Парсинг и обработка пакетов с учётом типов каналов и данных.

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

% Настройте параметры для HTTP‑методов PUT и GET:
% - MediaType: тип передаваемых данных;
% - Timeout: время ожидания ответа;
% - RequestMethod: метод запроса.
putOptions = weboptions('MediaType','application/x-www-form-urlencoded', 'Timeout', timeout, 'RequestMethod','put');
getOptions = weboptions('MediaType','application/json', 'Timeout', timeout, 'RequestMethod','get');

% Сбрасываем QServer к конфигурации по умолчанию, чтобы обеспечить известную начальную точку.
% Вы можете закомментировать этот раздел, если хотите настроить систему через QAcquire.
% webwrite(url + "system/settings/resetToDefaults", putOptions);

%% Поиск канала с включённой потоковой передачей
%
% Для получения данных через TCP‑соединение требуется канал,
% у которого активирована функция потоковой передачи.
foundStreamingChannel = false;  % Флаг: true, если найден подходящий канал
itemList = webread(url + "item/list", getOptions);  % Получаем полный список элементов от QServer
for index = 1:length(itemList)   % Перебираем элементы списка
    itemInfo = itemList(index);

    % Проверяем, является ли текущий элемент каналом (ItemTypeIdentifier == 4).
    if itemInfo.ItemTypeIdentifier == 4
        itemId = itemInfo.ItemId;
         % Получаем детальные настройки канала по его ID.
        channelSettings = webread(url + "item/settings/?itemId=" + itemId, getOptions);
       
         % Убедимся, что у канала есть настройки и данные, а режим работы активен.
        if ~isempty(channelSettings.Settings) && ~isempty(channelSettings.Data) && channelSettings.OperationMode.Id ~= 0
           % Ищем параметр «Состояние потоковой передачи» среди настроек канала.
            for dataIndex = 1:length(channelSettings.Data)
                if strcmp(channelSettings.Data(dataIndex).Name, "Streaming State") && channelSettings.Data(dataIndex).Value == 1
                    foundStreamingChannel = true;  % Устанавливаем флаг: найден канал с включённой потоковой передачей.
                    break;   % Прерываем внутренний цикл — канал найден.
                end
            end
        end
    end
    
    % Если подходящий канал уже найден, прерываем внешний цикл
    if foundStreamingChannel
        break;
    end
end

% Если нет каналов с потоковой передачей, выдать ошибку.
if ~foundStreamingChannel
    error("At least one analog channel needs to be enabled for streaming to proceed with this example.")
end

%% Установление TCP‑соединения с QServer
%
% Получаем номер порта для TCP‑соединения с QServer 
% отправив запрос к эндпоинту "datastream/setup"
response = webread(url + "datastream/setup", getOptions);
tcpPort = response.TCPPort;

% Создаём TCP‑клиент:
% - ip: IP‑адрес сервера (задан ранее);
% - tcpPort: порт, выделенный QServer для потоковой передачи;
% - ConnectTimeout: таймаут подключения (60 секунд)..
tcpClient = tcpclient(ip, tcpPort, 'ConnectTimeout', 60);

%% Потоковая передача и парсинг пакетов данных
%
% После установления TCP‑соединения QServer начинает передавать данные.
% Важно оперативно обрабатывать данные, чтобы избежать переполнения буфера.
% Данный пример демонстрирует парсинг одного пакета. Для непрерывной потоковой
% передачи необходимо реализовать цикл с многопоточностью или асинхронной обработкой.

% Определяем размер заголовка пакета (32 байта) для чтения.
packetHeaderSize = 32;
packetHeader = read(tcpClient, packetHeaderSize, 'uint8');

% Парсим отдельные поля из заголовка пакета.
sequenceNumber = typecast(packetHeader(1:8), 'uint64');
transitTimestamp = typecast(packetHeader(9:16), 'double');
bufferLevel = typecast(packetHeader(17:20), 'single');
payloadSize = typecast(packetHeader(21:24), 'uint32');
byteOrderMarker = typecast(packetHeader(25:28), 'uint32');
payloadType = typecast(packetHeader(29:32), 'uint32');

% Читаем полезную нагрузку согласно размеру, указанному в заголовке.
% Преобразуем payloadSize в double для корректной работы функции read.
payload = read(tcpClient, double(payloadSize), 'uint8');  

% В данном примере закрываем соединение для возможности пошаговой отладки.
% В реальной задаче соединие закрывается после сбора всех необходимых данных.
clear tcpClient;

% Обрабатываем данные только при поддерживаемом типе полезной нагрузки
% Тип 0: стандартный формат данных, включающий заголовки и блоки данных
if payloadType == 0
    % Инициализируем индекс для парсинга и счётчик каналов
    index = uint32(1);
    channelIndex = 1;

    % Цикл для парсинга данных каждого канала в полезной нагрузке.
    while index < payloadSize
        % Читаем общий заголовок канала (24 байта).
        genericChannelHeaderLength = 24;
        genericChannelHeader = typecast(payload(index:(index + genericChannelHeaderLength - 1)), 'uint8');
        index = index + genericChannelHeaderLength;
        
        % Извлекаем поля из общего заголовка канала..
        data(channelIndex).ChannelId = typecast(genericChannelHeader(1:4), 'int32');
        data(channelIndex).SampleType = typecast(genericChannelHeader(5:8), 'int32');
        data(channelIndex).ChannelType = typecast(genericChannelHeader(9:12), 'uint32');
        data(channelIndex).ChannelDataSize = typecast(genericChannelHeader(13:16), 'uint32');
        data(channelIndex).ChannelTimestamp = typecast(genericChannelHeader(17:24), 'uint64');
        
        % Парсим специфические заголовки и данные в зависимости от типа канала.
        switch data(channelIndex).ChannelType
            case 0 % Аналоговые каналы
                % Читаем специфический заголовок аналогового канала (20 байт).
                analogChannelHeader = payload(index:index + 19);
                index = index + 20;
                
                % Извлекаем параметры аналогового канала.
                data(channelIndex).ChannelIntegrity = typecast(analogChannelHeader(1:4), 'int32');
                data(channelIndex).LevelCrossingOccurred = typecast(analogChannelHeader(5:8), 'int32');
                data(channelIndex).Level = typecast(analogChannelHeader(9:12), 'single');
                data(channelIndex).Min = typecast(analogChannelHeader(13:16), 'single');
                data(channelIndex).Max = typecast(analogChannelHeader(17:20), 'single');

                % Обработка данных в зависимости от типа отсчётов (SampleType).
                if (data(channelIndex).SampleType == 0)
                    % SampleType 0: данные без масштабирования (формат single).
                    data(channelIndex).DataBlock = typecast(payload(index:index + data(channelIndex).ChannelDataSize - 1), 'single');
                else
                    % SampleType ≠ 0: требуется масштабирование (сырые данные).
                    scalingFactor = typecast(payload(index:index + 3), 'single');
                    index = index + 4;
                        
                    switch (data(channelIndex).SampleType)
                        case 1 % 16‑битные целые числа со знаком.
                            valuesAsInt = typecast(payload(index:index + data(channelIndex).ChannelDataSize - 1), 'int16');
                            data(channelIndex).DataBlock = typecast(valuesAsInt, 'single').*scalingFactor;
                            
                        case 2 %24‑битные целые числа (не поддерживаются в MATLAB напрямую)
                               % поэтому нужно преобразовать 3‑байтовое (24‑битное) целое число в 4‑байтовое (32‑битное)
                               % для дальнейшей обработки в MATLAB.

                                for sampleIndex = 1:(data(channelIndex).ChannelDataSize / 3)
                                    dataIndex = index + ((sampleIndex - 1) * 3);
                                    valueAsBytes = payload(dataIndex:dataIndex + 2);
                                    % Собираем 32‑битное целое из 3 байт.
                                    % Результат: младшие 8 бит равны 0 (сдвиг на 8 бит)
                                    valueAsInt = bitshift(int32(valueAsBytes(3)), 24) ...      % Старший байт → биты 31–24
                                                    + bitshift(int32(valueAsBytes(2)), 16) ... % Средний байт → биты 23–16
                                                    + bitshift(int32(valueAsBytes(1)), 8);     % Младший байт → биты 15–8
                                                
                                    data(channelIndex).DataBlock(sampleIndex) = single(valueAsInt) * scalingFactor;
                                end
                            
                        case 3 % 32‑битные целые числа со знаком.
                            valuesAsInt = typecast(payload(index:index + data(channelIndex).ChannelDataSize - 1), 'int32'); 
                            data(channelIndex).DataBlock = typecast(valuesAsInt, 'single').*scalingFactor;
                            
                        otherwise
                            error("An invalid SampleType was sent and cannot be parsed.")
                    end
                end

                index = index + data(channelIndex).ChannelDataSize;
                
            case 1 % Тахометрические каналы
                % У тахометрических каналов нет специфического заголовка.
                % Читаем данные напрямую в блок
                data(channelIndex).DataBlock = typecast(payload(index:index + data(channelIndex).ChannelDataSize - 1), 'double');
                index = index + data(channelIndex).ChannelDataSize;
        
            case 2 % CAN‑каналы
                % Пропускаем 24 байта зарезервированного заголовка.
                index = index + 24;
                
                % Парсим CAN‑сообщения
                messageIndex = 1;
                endIndex = index + data(channelIndex).ChannelDataSize;
                while (index < endIndex)
                    data(channelIndex).DataBlock(messageIndex).Timestamp = typecast(payload(index:index+7), 'double');
                    data(channelIndex).DataBlock(messageIndex).Id = typecast(payload(index+8:index+11), 'uint32');
                    data(channelIndex).DataBlock(messageIndex).Header = payload(index+12);
                    data(channelIndex).DataBlock(messageIndex).FrameFormat = payload(index+13);
                    data(channelIndex).DataBlock(messageIndex).FrameType = payload(index+14);
                    data(channelIndex).DataBlock(messageIndex).DataFieldLength = uint32(payload(index+15));
                    data(channelIndex).DataBlock(messageIndex).Data = payload(index+16:index+16+data(channelIndex).DataBlock(messageIndex).DataFieldLength-1);
                     
                    index = index + 16 + data(channelIndex).DataBlock(messageIndex).DataFieldLength;
                end
                
            case 3 % GPS‑каналы (бета‑версия)
                % Читаем специфический заголовок GPS.
                data(channelIndex).Timestamp = typecast(payload(index:index+7), 'double');
                data(channelIndex).AccuracyEstimate = typecast(payload(index+8:index+9), 'uint16');
                data(channelIndex).IsLeapSecondsValid = payload(index+10);
                data(channelIndex).LeapSeconds = payload(index+11);
                index = index + 12;
                
                 % Читаем GPS‑сообщение.
                data(channelIndex).Message = char(payload(index:index + data(channelIndex).ChannelDataSize - 1));
                index = index + data(channelIndex).ChannelDataSize;
                
                disp(data(channelIndex).Message);
        end
        
        % Не забываем увеличить индексы для следуюещего канала.
        channelIndex = channelIndex + 1;
    end
end

% Напоминание: закройте TCP‑сокет, если он ещё не закрыт.
clear tcpClient;

%% Дополнительная информация
%
% Подробную информацию о параметрах настройки и конфигурациях
% см. в руководстве пользователя QServer.
%
% Дополнительные примеры и документацию
% можно найти в репозиториях ORION-DAQ: % https://github.com/ORION-DAQ
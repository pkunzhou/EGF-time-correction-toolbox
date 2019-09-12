function [signalStruct] = ReadMSEEDFast(fileName)
% ReadMSEEDFast( fileName )
% reads MSEED file and returns record structure.
% Whole MSEED file is loaded to memory and
% the file is processed in memory. 
% Loops were vectorised as much as possible.
%
% This version is optimalized for speed and supports
% only subset of MSEED format:
%
% Chunks in traces are assumed to be chronologicaly
% saved. Interlaced traces are not supported.
%
% The file is assumed to have just one encoding type.
% Usage of more than one encoding format in the file
% is not supported yet.
%
% Just DATAONLY blockett is supported yet.
% Other blocketts will be add in the future.
%
% Supported data encoding formats:
%
% ANSI CHAR                    (format code  0 )
% big endian, little endian  
% INT16                        (format code  1 )
% INT32                        (format code  3 )
% FLOAT32                      (format code  4 )
% DOUBLE                       (format code  5 )
% STEIM1                       (format code 10 )
% STEIM2                       (format code 11 )
%
%
%
% input : fileName
% output: record structure matrix
%
%  Record structure fields:
%
%  network          - string
%  station          - string
%  location         - string
%  channel          - string
%  dataquality      - string
%  type             - string
%  startTime        - double
%  endTime          - double
%  sampleRate       - double
%  sampleCount      - long int
%  numberOfSamples  - long int
%  sampleType       - string ( i for integer)
%  data             - vector of doubles
%  dateTime         - struct (all doubles)
%                     year
%                     month
%                     day
%                     hour
%                     minute
%                     second
%  dateTimeString   - string
%  matlabTimeVector - vector of Matlab time stamps for each data sample 
%                     (generated by datenum function)
%
%
% Code is partially based on rdmmseed.m by
% Franois Beauducel <beauducel@ipgp.fr>
% Institut de Physique du Globe de Paris
%
% credit  : Martin Mityska (2014)
%           Faculty of Science
%           Charles University in Prague
% version : 1.3 - 06 / 2015
%           added bitcmpOld function to mimic old funcionality of bitcmp
%	    important for new MATLABs like version R2014.
% version : 1.4 - 06 / 2015
%	    Division changed to element-wise, change of line 479.
%           Old code: sampleRate = 1/(sampleRateFactor.*sampleRateMultiplier);
%           New code: sampleRate = 1./(sampleRateFactor.*sampleRateMultiplier);
% version : 1.5 - 03 / 2017
%	    Support for multiple logical volumes in MSEED file added.
%       At first, logical volumes are found and further processing is done
%       inside the volumes (unique stations and channels inside the single 
%       logical volume are identified).
% version : 1.6 - 04 / 2017
%	    Time vector for each result struct data vector added.
%       matlabTimeVector field contains time stamps for every sample in
%       data vector.
%       Time values are Matlab time stamps generated by datenum function
%       from MSEED header blocks.
% version : 1.7 - 06 / 2017
%       Bug fixed - time stamps routine neglected fractions of seconds - fixed.

    % Endian flag - big endian as default
    isLittleEndian = 0;

    % Encoding flag - STEIM 2 as default
    ENCODING = 11;

    % This structure will be filled with data and returned
    signalStruct = [];

    % Opening file and loading raw data
    try
        fp = fopen(fileName,'r');
        raw = fread(fp)';
    catch err
        signalStruct = -1;
        error(sprintf('Error occured during opening file:\n%s\nDetails:\n %s\n',fileName,err.identifier));
        return 
    end

    % Let's announce what we are reading
    fprintf('ReadMSEEDFast:\t%s\n',fileName);
    
    % Big / Little endian test
    Year = typecast(uint8(raw(20:21)),'uint16');
    if Year >= 2056
        isLittleEndian = 1;
    end
    
    %Let's read first header and estimate block record size (4096 bytes is
    %recommended length according to IRIS specification.
    firstHeader = ReadHeaders(typecast(uint8(raw),'uint8'),isLittleEndian);
    
    BLOCK_RECORD_SIZE=firstHeader.dataRecordLength;
    
    % Reshaping linear data to matrix form
    rawPacketMatrix = reshape(typecast(uint8(raw),'uint8'),BLOCK_RECORD_SIZE,[])';
    rawPacketMatrixSize = size(rawPacketMatrix);

    % Reading all headers of the file at once
    [headerInfoAllVolumes] = ReadHeaders(rawPacketMatrix,isLittleEndian);

    ENCODING=headerInfoAllVolumes.encoding(1);
    
    % Decoding data for every unique station and channel on the record
    logicalVolumesStartIndex=sort(find(headerInfoAllVolumes.sequenceNumber==1));
    
    if isempty(logicalVolumesStartIndex)
        logicalVolumesStartIndex=1;
    end
    
    for v=1:numel(logicalVolumesStartIndex)
        
        headerInfo = [];
    if v~=numel(logicalVolumesStartIndex)
        headerInfo = struct('stationCode',{{headerInfoAllVolumes.stationCode{1}(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1)}},'locationCode',{{headerInfoAllVolumes.locationCode{1}(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1)}},'channelId',{{headerInfoAllVolumes.channelId{1}(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1)}},'networkCode',{{headerInfoAllVolumes.networkCode{1}(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1)}},'nSamples',headerInfoAllVolumes.nSamples(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1),'sampleRate',headerInfoAllVolumes.sampleRate(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1),'nFolowingBlocketts',headerInfoAllVolumes.nFolowingBlocketts(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1),'timeCorrection',headerInfoAllVolumes.timeCorrection(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1),'dataBeginOffset',headerInfoAllVolumes.dataBeginOffset(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1),'blockettBeginOffset',headerInfoAllVolumes.blockettBeginOffset(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1),'startTime',headerInfoAllVolumes.startTime(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1,:),'encoding',headerInfoAllVolumes.encoding(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1),'wordOrder',headerInfoAllVolumes.wordOrder(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1),'dataRecordLength',headerInfoAllVolumes.dataRecordLength(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1),'sequenceNumber',headerInfoAllVolumes.sequenceNumber(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1),'dataQualityCode',headerInfoAllVolumes.dataQualityCode(logicalVolumesStartIndex(v):logicalVolumesStartIndex(v+1)-1));
    else
        headerInfo = struct('stationCode',{{headerInfoAllVolumes.stationCode{1}(logicalVolumesStartIndex(v):end)}},'locationCode',{{headerInfoAllVolumes.locationCode{1}(logicalVolumesStartIndex(v):end)}},'channelId',{{headerInfoAllVolumes.channelId{1}(logicalVolumesStartIndex(v):end)}},'networkCode',{{headerInfoAllVolumes.networkCode{1}(logicalVolumesStartIndex(v):end)}},'nSamples',headerInfoAllVolumes.nSamples(logicalVolumesStartIndex(v):end),'sampleRate',headerInfoAllVolumes.sampleRate(logicalVolumesStartIndex(v):end),'nFolowingBlocketts',headerInfoAllVolumes.nFolowingBlocketts(logicalVolumesStartIndex(v):end),'timeCorrection',headerInfoAllVolumes.timeCorrection(logicalVolumesStartIndex(v):end),'dataBeginOffset',headerInfoAllVolumes.dataBeginOffset(logicalVolumesStartIndex(v):end),'blockettBeginOffset',headerInfoAllVolumes.blockettBeginOffset(logicalVolumesStartIndex(v):end),'startTime',headerInfoAllVolumes.startTime(logicalVolumesStartIndex(v):end,:),'encoding',headerInfoAllVolumes.encoding(logicalVolumesStartIndex(v):end),'wordOrder',headerInfoAllVolumes.wordOrder(logicalVolumesStartIndex(v):end),'dataRecordLength',headerInfoAllVolumes.dataRecordLength(logicalVolumesStartIndex(v):end),'sequenceNumber',headerInfoAllVolumes.sequenceNumber(logicalVolumesStartIndex(v):end),'dataQualityCode',headerInfoAllVolumes.dataQualityCode(logicalVolumesStartIndex(v):end));
    end
     
    [stations uniqueStationsIndex]=unique(headerInfo.stationCode{1});
    [channels uniqueChannelsIndex]=unique(headerInfo.channelId{1});
    channels=flipud(channels);
    stations=flipud(stations);
    uniqueChannelsIndex=sort(flipud(uniqueChannelsIndex));
    uniqueStationsIndex=sort(flipud(uniqueStationsIndex));
    
    
    for h=1:numel(stations)
        for k=1:numel(channels)

                sameChannelRows=find((strcmp(headerInfo.channelId{1},channels(k)) & strcmp(headerInfo.stationCode{1},stations(h))))+(logicalVolumesStartIndex(v)-1);
                
                encodedSignalMatrix = rawPacketMatrix(sameChannelRows,headerInfo.dataBeginOffset(1)+1:rawPacketMatrixSize(2));
                [signalMatrix,timeVector]=DecodeSignal(encodedSignalMatrix,ENCODING,isLittleEndian,BLOCK_RECORD_SIZE,headerInfoAllVolumes.startTime(sameChannelRows,:),headerInfoAllVolumes.sampleRate(sameChannelRows,:));

                %uci - unique channel index
                uci = 1;
                switch k
                    case 1
                    uci = 1;
                    otherwise
                    uci = uniqueChannelsIndex(k-1)+1;
                end

                [dtStruct, dtString, unixTimeStamp]=ConstructDateTime(headerInfo.startTime(uci,:));
                
                %Data type of the file
                sampleType = 'i';
                
                switch(ENCODING)
                    case 4
                        %Float sample type
                        sampleType = 'f';
                    case 5
                        %Double sample type
                        sampleType = 'd';
                    otherwise
                        %Integer sample type
                        sampleType = 'i';
                end
                
                % Prepare result struct
                sameChannelRows=sameChannelRows-(logicalVolumesStartIndex(v)-1);
                signalStruct=[signalStruct;struct('network',headerInfo.networkCode{1}(sameChannelRows(1)),'station',headerInfo.stationCode{1}(sameChannelRows(1)),'location',headerInfo.locationCode{1}(sameChannelRows(1)),'channel',headerInfo.channelId{1}(sameChannelRows(1)),'dataquality','','type','','startTime',unixTimeStamp,'endTime',0,'sampleRate',double(headerInfo.sampleRate(sameChannelRows(1))),'sampleCount',size(signalMatrix,1),'numberOfSamples',size(signalMatrix,1),'sampleType',sampleType,'data',signalMatrix(:),'dateTime',dtStruct,'dateTimeString',dtString,'matlabTimeVector',timeVector)];

        end
    end
    end
    fclose(fp);

end

function output = bitcmpOld(x,N)

      %output=bitcmp(x,N); %for older matlab releases before R2014a uncomment this line and comment out the rest of the function.
       if nargin < 2
 
           output = bitcmp(x);
 
       else
 
           maxN = 2^N-1;    % This is the max number you can represent in 4 bits
 
           fmt  = 'uint32';  % You can change uint8 to uint16 or 32
 
           out1 = eval(['bitcmp(',fmt,'(x)',',''',fmt,''')']);
 
           out2 = eval(['bitcmp(',fmt,'(maxN)',',''',fmt,''')']);
 
           output = out1 - out2;
 
       end

end

function [trace,timeVector] = DecodeSignal(encodedSignalMatrix, encodingFormat,isLittleEndian,BLOCK_RECORD_SIZE,startTimeChunks,sampleRateChunks)
    
    timeVector = [];

    % Decoding routine for STEIM2 only
    switch encodingFormat
        
%         Todo add support for next encoding formats
         case 0
%             % --- decoding format: ASCII text
             signalMatrix=TypeCastArray((reshape(encodedSignalMatrix',1,[])')','int8');
            
             trace = signalMatrix;

% 
         case 1
%             % --- decoding format: 16-bit integers
             signalMatrix=TypeCastArray((reshape(encodedSignalMatrix',2,[])')','int16');
            
             if ~isLittleEndian
                 signalMatrix=swapbytes(signalMatrix(:));
             end
            
             trace = signalMatrix;
 		
%         case 2
%             % --- decoding format: 24-bit integers
              % unsupported 

         case 3
            % --- decoding format: 32-bit integers
            signalMatrix=TypeCastArray((reshape(encodedSignalMatrix',4,[])')','int32');
            
            if ~isLittleEndian
                signalMatrix=swapbytes(signalMatrix(:));
            end
            
            trace = signalMatrix;


         case 4
            % --- decoding format: IEEE floating point
            %D.EncodingFormatName = 'FLOAT32';
            
            %retype file to float32
            signalMatrix=TypeCastArray((reshape(encodedSignalMatrix',4,[])')','single');
            
            if ~isLittleEndian
                signalMatrix=swapbytes(signalMatrix(:));
            end
            
            trace = signalMatrix;
 
     	case 5
%             % --- decoding format: IEEE double precision floating point
            signalMatrix=TypeCastArray((reshape(encodedSignalMatrix',8,[])')','double');
            
            if ~isLittleEndian
                signalMatrix=swapbytes(signalMatrix(:));
            end
            
            trace = signalMatrix;


        case {10,11,19}
            steim = find(encodingFormat==[10,11,19]);
            
            signalMatrix=TypeCastArray((reshape(encodedSignalMatrix',4,[])')','uint32');
            
            if ~isLittleEndian
                signalMatrix=swapbytes(signalMatrix(:));
            end
            
            signalMatrix=reshape(signalMatrix,numel(encodedSignalMatrix(1,:))/4,[]);

            % read first int from every 64 int chunk (contains encoded nibbles)
            Q=signalMatrix(1:16:size(signalMatrix(:,1)),:);
            % reshape to one long column
            Q=reshape(Q,size(Q,1)*size(Q,2),1)';
            % prepare matrix Q for bitshift
            Q=repmat(Q,16,1);
            % prepare bit mask for bitshift
            bshiftMask=repmat(-30:2:0,size(Q,2),1)';
            bQ=bitshift(Q,bshiftMask);
            % decode nibbles
            nibbles = bitand(bQ,bitcmpOld(0,2));
            % forward integration constant
            x0 = bitsign(signalMatrix(2,:),32);	
            %x0(1)
            % reverse integration constant
            xn = bitsign(signalMatrix(3,:),32);	
            
            % How many values can be stored in one chunk - depends on encoding
            maxValuesInChunk = 0;

            switch steim
                
                case 1
                    % STEIM-1: 3 cases following the nibbles
                    
                    maxValuesInChunk = 4;
                                        
                    ddd = NaN*ones(4,numel(signalMatrix));	% initiates array with NaN
                    k = find(nibbles == 1);			% nibble = 1 : four 8-bit differences
                    if ~isempty(k)
                        ddd(1:4,k) = bitsplit(signalMatrix(k),32,8);
                        
                        if isLittleEndian
                            ddd(1:4,k)=flipud(ddd(1:4,k));
                        end
                        
                    end
                    k = find(nibbles == 2);			% nibble = 2 : two 16-bit differences
                    if ~isempty(k)
                        ddd(1:2,k) = bitsplit(signalMatrix(k),32,16);
                        
                        if isLittleEndian
                            ddd(1:4,k)=flipud(ddd(1:4,k));
                        end
                        
                    end
                    k = find(nibbles == 3);			% nibble = 3 : one 32-bit difference
                    if ~isempty(k)
                        ddd(1,k) = bitsign(signalMatrix(k),32);
                    end
                    
                
                case 2	
                % STEIM-2: 7 cases following the nibbles and dnib
                
                    maxValuesInChunk = 7;
                
                    ddd = NaN*ones(7,numel(signalMatrix));	% initiates array with NaN
                    k = find(nibbles == 1);			% nibble = 1 : four 8-bit differences
                    if ~isempty(k)
                        ddd(1:4,k) = bitsplit(signalMatrix(k),32,8);
                        
                        if isLittleEndian
                            ddd(1:4,k)=flipud(ddd(1:4,k));
                        end
                        
                    end
                    k = find(nibbles == 2);			% nibble = 2 : must look in dnib
                    if ~isempty(k)
                        dnib = bitshift(signalMatrix(k),-30);
                        kk = k(dnib == 1);		% dnib = 1 : one 30-bit difference
                        if ~isempty(kk)
                            ddd(1,kk) = bitsign(signalMatrix(kk),30);
                        end
                        kk = k(dnib == 2);		% dnib = 2 : two 15-bit differences
                        if ~isempty(kk)
                            ddd(1:2,kk) = bitsplit(signalMatrix(kk),30,15);
                        end
                        kk = k(dnib == 3);		% dnib = 3 : three 10-bit differences
                        if ~isempty(kk)
                            ddd(1:3,kk) = bitsplit(signalMatrix(kk),30,10);
                        end
                    end
                    k = find(nibbles == 3);				% nibble = 3 : must look in dnib
                    if ~isempty(k)
                        dnib = bitshift(signalMatrix(k),-30);
                        kk = k(dnib == 0);		% dnib = 0 : five 6-bit difference
                        if ~isempty(kk)
                            ddd(1:5,kk) = bitsplit(signalMatrix(kk),30,6);
                        end
                        kk = k(dnib == 1);		% dnib = 1 : six 5-bit differences
                        if ~isempty(kk)
                            ddd(1:6,kk) = bitsplit(signalMatrix(kk),30,5);
                        end
                        kk = k(dnib == 2);		% dnib = 2 : seven 4-bit differences (28 bits!)
                        if ~isempty(kk)
                            ddd(1:7,kk) = bitsplit(signalMatrix(kk),28,4);
                        end
                    end
                    
               end
                   
               % Building matrix of column vectors of signal from
               % data blocks
               ddd=reshape(ddd,[],1);
                             
               if mod(size(ddd,1),((BLOCK_RECORD_SIZE-64)/4)*maxValuesInChunk) ~= 0
                   ddd = [ddd; nan*zeros(((BLOCK_RECORD_SIZE-64)/4)*maxValuesInChunk-mod(size(ddd,1),((BLOCK_RECORD_SIZE-64)/4)*maxValuesInChunk),1)];
               end

               blockMatrix=reshape(ddd,((BLOCK_RECORD_SIZE-64)/4)*maxValuesInChunk,[]);
                              
               % Removing NaNs and adding integration constant to every 
               % vector in block matrix, than building to trace vector
               trace = [];
               
               mdate = datenum(double(startTimeChunks(:,1))-1, 12, 31, 0, 0, 0) + double(startTimeChunks(:,2))+double(startTimeChunks(:,3))./24+double(startTimeChunks(:,4))./(24*60)+(double(startTimeChunks(:,5))./(24*3600))+double(double(startTimeChunks(:,6))./1e4)./double(24*3600);
               
               for i=1:size(blockMatrix,2)
                   column = blockMatrix(~isnan(blockMatrix(:,i)),i);
                   column = cumsum([x0(i);column(2:numel(column))]);
                   timeVector=[timeVector;mdate(i) + (0:(numel(column)-1))'./(double(sampleRateChunks(i)).*86400)];
                   trace = [trace;column];
               end
               
        otherwise
            trace = [0];
            timeVector=[0];
            errorMsg = sprintf('Error: unknown data encoding.\n Supported formats are STEIM1, STEIM2.\n');
            fprintf(2,errorMsg);
            return
            
    end
  
end

function [encoding,wordOrder,dataRecordLength] = ReadBlockets(raw,nFolowingBlocketts,blockettBeginOffset,isLittleEndian)

    % We read only first blockette in stream to get encoding format
    % We assume that there is only one encoding format used for the whole file
    
    if isLittleEndian
        BlocketType = TypeCastArray(raw(:,(blockettBeginOffset(1)+1:blockettBeginOffset(1)+2))','int16');
        nextBlocketOffset = 0;
        switch(BlocketType(1))
            case 1000 % Data only blockette
                nextBlocketOffset = TypeCastArray(raw(:,(blockettBeginOffset(1)+3:blockettBeginOffset(1)+4))','int16');

                EncodingFormat = TypeCastArray(raw(:,blockettBeginOffset(1)+5)','uint8');
                WordOrder = TypeCastArray(raw(:,blockettBeginOffset(1)+6)','uint8');
                DataRecordLength = TypeCastArray(raw(:,blockettBeginOffset(1)+7)','uint8');
        end
    else
        
        BlocketType = swapbytes(TypeCastArray(raw(:,(blockettBeginOffset(1)+1:blockettBeginOffset(1)+2))','int16'));
        nextBlocketOffset = 0;
        switch(BlocketType(1))
            case 1000 % Data only blockette
                nextBlocketOffset = swapbytes(TypeCastArray(raw(:,(blockettBeginOffset(1)+3:blockettBeginOffset(1)+4))','int16'));

                EncodingFormat = TypeCastArray(raw(:,blockettBeginOffset(1)+5)','uint8');
                WordOrder = TypeCastArray(raw(:,blockettBeginOffset(1)+6)','uint8');
                DataRecordLength = TypeCastArray(raw(:,blockettBeginOffset(1)+7)','uint8');
        end
        
    end
    
    encoding=EncodingFormat;
    wordOrder=WordOrder;
    dataRecordLength=DataRecordLength;

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [headerInfo] = ReadHeaders(raw,isLittleEndian)

% Reading values from all headers at once
% swapbytes swaps values to little endian

    sequenceNumber = str2num(char(raw(:,1:6)));
    dataQualityCode = char(raw(:,7));

    stationCode = char(raw(:,9:13));
    stationCode = char(raw(:,9:13));
    locationCode = char(raw(:,14:15));
    channelId = char(raw(:,16:18));
    networkCode = char(raw(:,19:20));
    startTime = ReadBTime(raw(:,21:30),isLittleEndian);

    if ~isLittleEndian
        nSamples = swapbytes(TypeCastArray(raw(:,31:32)','uint16'));
        sampleRateFactor = swapbytes(TypeCastArray(raw(:,33:34)','int16'));
        sampleRateMultiplier = swapbytes(TypeCastArray(raw(:,35:36)','int16'));

        nFolowingBlocketts = swapbytes(TypeCastArray(raw(:,40)','uint8'));
        timeCorrection = swapbytes(TypeCastArray(raw(:,41:44)','uint32'));
        dataBeginOffset = swapbytes(TypeCastArray(raw(:,45:46)','uint16'));
        blockettBeginOffset = swapbytes(TypeCastArray(raw(:,47:48)','uint16'));
    else
        nSamples = TypeCastArray(raw(:,31:32)','uint16');
        sampleRateFactor = TypeCastArray(raw(:,33:34)','int16');
        sampleRateMultiplier = TypeCastArray(raw(:,35:36)','int16');

        nFolowingBlocketts = TypeCastArray(raw(:,40)','uint8');
        timeCorrection = TypeCastArray(raw(:,41:44)','uint32');
        dataBeginOffset = TypeCastArray(raw(:,45:46)','uint16');
        blockettBeginOffset = TypeCastArray(raw(:,47:48)','uint16');
    end
    
    % vector of sample rate values for every block
    sampleRate = zeros(size(sampleRateFactor));

    if sampleRateFactor > 0
        if sampleRateMultiplier >= 0
            sampleRate = sampleRateFactor.*sampleRateMultiplier;
        else
            sampleRate = -1*sampleRateFactor./sampleRateMultiplier;
        end
    else
        if sampleRateMultiplier >= 0
            sampleRate = -1*sampleRateMultiplier./sampleRateFactor;
        else
            sampleRate = 1./(sampleRateFactor.*sampleRateMultiplier);
        end
    end
    
    try
        [encoding,wordOrder,dataRecordLength]=ReadBlockets(raw,nFolowingBlocketts,blockettBeginOffset,isLittleEndian);
        dataRecordLength=2.^double(dataRecordLength);
    catch
        warning('Cannot read blockette 1000 - data only blockette\nTrying STEIM2 encoding');
        encoding = 11; % 11 is Steim2 code
        dataRecordLength=4096; %defaults,'sequenceNumber'
        wordOrder=1; %big endian as default
    end
    
    headerInfo = struct('stationCode',{{cellstr(stationCode)}},'locationCode',{{cellstr(locationCode)}},'channelId',{{cellstr(channelId)}},'networkCode',{{cellstr(networkCode)}},'nSamples',nSamples,'sampleRate',sampleRate,'nFolowingBlocketts',nFolowingBlocketts,'timeCorrection',timeCorrection,'dataBeginOffset',dataBeginOffset,'blockettBeginOffset',blockettBeginOffset,'startTime',startTime,'encoding',encoding,'wordOrder',wordOrder,'dataRecordLength',dataRecordLength,'sequenceNumber',sequenceNumber,'dataQualityCode',dataQualityCode);

end

function NewArray = TypeCastArray(theArray, newType)
  NewArray = typecast(theArray(:),newType);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function d = ReadBTime(bTime,isLittleEndian)
% readbtime(FID) reads BTIME structure from current file and returns
%	D = [YEAR,DAY,HOUR,MINUTE,SECONDS]
    if ~isLittleEndian
        Year					= swapbytes(TypeCastArray(bTime(:,1:2)','uint16'));
        DayOfYear				= swapbytes(TypeCastArray(bTime(:,3:4)','uint16'));
        Hours					= swapbytes(TypeCastArray(bTime(:,5)','uint8'));
        Minutes					= swapbytes(TypeCastArray(bTime(:,6)','uint8'));
        Seconds					= swapbytes(TypeCastArray(bTime(:,7)','uint8'));
        unused					= swapbytes(TypeCastArray(bTime(:,8)','uint8'));
        Seconds0001				= swapbytes(TypeCastArray(bTime(:,9:10)','uint16'));
    else
        Year					= TypeCastArray(bTime(:,1:2)','uint16');
        DayOfYear				= TypeCastArray(bTime(:,3:4)','uint16');
        Hours					= TypeCastArray(bTime(:,5)','uint8');
        Minutes					= TypeCastArray(bTime(:,6)','uint8');
        Seconds					= TypeCastArray(bTime(:,7)','uint8');
        unused					= TypeCastArray(bTime(:,8)','uint8');
        Seconds0001				= TypeCastArray(bTime(:,9:10)','uint16');
    end

    d = [Year,DayOfYear,Hours,Minutes,uint16(Seconds),Seconds0001];

end

function [dateTimeStruct, dateTimeString, unixTimeStamp, matlabTimeStamp]= ConstructDateTime(dateTimeMatrix)

    days = [31,28,31,30,31,30,31,31,30,31,30,31];
    month = 1;
    day = 1;
    dayInYear = dateTimeMatrix(2);

     if mod(dateTimeMatrix(1)-2000,4) == 0
           days(2) = 29;
     end

    monthsDaysCumsum=cumsum(days);
    for k = 1:numel(monthsDaysCumsum)
        if dayInYear <= monthsDaysCumsum(k)
            month = k;
            if k == 1
                day = dayInYear;    
                break;
            end
            day = dayInYear - monthsDaysCumsum(k-1);
            break;
        end
    end

    dvec=datevec(datenum([double(dateTimeMatrix(1)),double(month),double(day),double(dateTimeMatrix(3)),double(dateTimeMatrix(4)),double(dateTimeMatrix(5))+double(dateTimeMatrix(6))./1e4]));

    year=dvec(1);
    month=dvec(2);
    day=dvec(3);
    hour=dvec(4);
    minute=dvec(5);
    second=dvec(6);

    dateTimeStruct = struct('year',year,'month',month,'day',day,'hour',hour,'minute',minute,'second',second);
    dateTimeString=sprintf('%04d/%02d/%02d %02d:%02d:%02f',dateTimeStruct.year,dateTimeStruct.month,dateTimeStruct.day,dateTimeStruct.hour,dateTimeStruct.minute,dateTimeStruct.second);
    matlabTimeStamp=datenum([dateTimeStruct.year,dateTimeStruct.month,dateTimeStruct.day,dateTimeStruct.hour,dateTimeStruct.minute,dateTimeStruct.second]);
    unixTimeStamp=FromMatlabTimeToUnixTime(matlabTimeStamp);
end

function [day] = daysInMonth(month, year)

    days = [31,28,31,30,31,30,31,31,30,31,30,31];

    day = days(month);

    if month == 2
       if mod(year-2000,4) == 0
           day = 29;
       end
    end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function d = bitsign(x,n)
% bitsign(X,N) returns signed double value from unsigned N-bit number X.
% This is equivalent to bitsplit(X,N,N), but the formula is simplified so
% it is much more efficient

    d = double(bitand(x,bitcmpOld(0,n))) - double(bitget(x,n)).*2^n;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function d = bitsplit(x,b,n)
% bitsplit(X,B,N) splits the B-bit number X into signed N-bit array
%	X must be unsigned integer class
%	N ranges from 1 to B
%	B is a multiple of N

    sign = repmat((b:-n:n)',1,size(x,1));
    x = repmat(x',b/n,1);
    d = double(bitand(bitshift(x,flipud(sign-b)),bitcmpOld(0,n))) ...
        - double(bitget(x,sign))*2^n;
end

function [unixTime] = FromMatlabTimeToUnixTime(dateTime)
    % 12*24*60*60 = 86400 - Conversion from Unix Posix Time to Matlab Time
    pivotYear1970 = datenum('1970', 'yyyy');
    if isstruct(dateTime)
        dateTimeVec = [dateTime.year,dateTime.month,dateTime.day,dateTime.hour,dateTime.minute,dateTime.second];
    elseif isvector(dateTime)
        dateTimeVec = dateTime;
    elseif isscalar(dateTime)
        unixTime=dateTime-pivotYear1970;
        unixTime=unixTime*86400;
        return;
    end

    unixTime=datenum(dateTimeVec)-pivotYear1970;
    unixTime=unixTime*86400;

end

function [matlabTime] = FromUnixTimeToMatlabTime(unixTime)
    % 12*24*60*60 = 86400 - Conversion from Unix Posix Time to Matlab Time
    matlabTime=datenum(unixTime/(86400)+datenum('1970', 'yyyy'));
end
% This program takes the timetables that were made in the
% LiDAR_GPS_IMU_Timetable_Maker function and creates a combined point
% cloud. 


clear all; close all; clc;

% Querey for files
gps_mat     = uigetfile('*.mat','Grab GPS file');
imu_mat     = uigetfile('*.mat','Grab IMU file');
lidar_mat   = uigetfile('*.mat','Grab LiDAR file');
% % 
% %     gps_mat = '/media/autobuntu/chonk/chonk/git_repos/Rural-Road-Lane-Creator/Sensor_Van_Rosbag_Handler/Point_Cloud_Maker/TimeTable_Export/Bean_Hoolloow/GPS_TimeTable.mat';
% %     imu_mat = '/media/autobuntu/chonk/chonk/git_repos/Rural-Road-Lane-Creator/Sensor_Van_Rosbag_Handler/Point_Cloud_Maker/TimeTable_Export/Bean_Hoolloow/IMU_TimeTable.mat';
% %     lidar_mat = '/media/autobuntu/chonk/chonk/git_repos/Rural-Road-Lane-Creator/Sensor_Van_Rosbag_Handler/Point_Cloud_Maker/TimeTable_Export/Bean_Hoolloow/LiDAR_TimeTable.mat';
% %     
% Load Files
disp('Loading files...')
load(gps_mat);
load(imu_mat);
load(lidar_mat);
disp('Loading complete!')

% Querey for export location
% export_dir      = uigetdir( '/media/autobuntu/chonk/chonk/git_repos/Rural-Road-Lane-Creator/Sensor_Van_Rosbag_Handler/Point_Cloud_Maker','Grab PCD Export Directory');

%     export_dir = '/media/autobuntu/chonk/chonk/git_repos/Rural-Road-Lane-Creator/Sensor_Van_Rosbag_Handler/Point_Cloud_Maker/PCD_Export/Simms_Something'

% VAR INIT SECTION

%% Get number of point cloud files
num_pc              = length(LiDAR_TimeTable.Data);

close all; clc;

% RPM of the LiDAR    
RPM                                             = 900;

% Device Model (string): VLP16 VLP32C HDL32E HDL64E VLS128
device_model                                    = "VLP32C";

% Number of channels
num_channels                                    = 32;

%     XYZI_Apphend        = zeros((115744 * num_pc), 4);
%     XYZI_Apphend        = []; % Resetting because i don't want to bug fix the more efficient method, it's pretty fast anyways so I'm probably not going to bother.

PCD_ROT_OFFSET      = rotz(90);
dydx_store_test     = [];
dxy_store           = [];

% Variable for converting GPS coordinates into meters
wgs84               = wgs84Ellipsoid;

% For loop for loading each point cloud, and adjusting using the gps
% and imu data

disp('Processing...')

%     f = waitbar(0,'1','Name','Doing Da Data');

% loop_array = 1:1:num_pc;
loop_array = 1:1:100;
for i = loop_array

%         % Safety, I feel better knowing it's here
%         if i > num_pc
%             disp('wow I''m glad I put this here'); break;
%         end

    %% HANDLING GPS

    [gps_time_diff(i),gps_ind]         = min(abs(GPS_TimeTable.Time(:) - LiDAR_TimeTable.Time(i)));
    
    gps_closest_time(i)     = GPS_TimeTable.Time(gps_ind);
    lidar_time_stamp(i)     = LiDAR_TimeTable.Time(i);
    
    % Set vars
    lat(i)                  = GPS_TimeTable.Data(gps_ind,1);
    lon(i)                  = GPS_TimeTable.Data(gps_ind,2);
    alt                     = GPS_TimeTable.Data(gps_ind,3);
    
    % Setting Local Coords for the first thing in the list        
    if i == loop_array(1)
        
        lat_start           = double(lat(i));
        lon_start           = double(lon(i));
        alt_start           = double(alt);
        origin              = [lat_start lon_start alt_start];
        
        dx = 0; dy = 0; vect(i) = 0;
        
        % Debugging junk
        dydx_store_test = [dydx_store_test; dx dy alt vect(i)];
        
        speed(i) = 0;
        
        duration_gps(i) = 0;
        duration_lidar(i) = 0;
        
    else

        [dx, dy, ~] = geodetic2ned(lat(i), lon(i), alt, lat_start, lon_start, alt_start, wgs84);
        
        vect(i)                 = sqrt(dx^2 + dy^2);
        
        d_vect(i)               = vect(i) - vect(i-1);
        
        duration_gps(i)         = gps_closest_time(i) - gps_closest_time(i-1);
        duration_lidar(i)       = lidar_time_stamp(i) - lidar_time_stamp(i-1);
        
        speed(i)                = d_vect(i) / duration_gps(i);
        
    end
    
    dydx_store_test = [dydx_store_test; dx dy alt vect(i)];
    
    %% HANDLING IMU

    % Closest IMU time point
    [imu_time_diff(i),imu_ind]         = min(abs(IMU_TimeTable.Time(:) - LiDAR_TimeTable.Time(i)));
    imu_closest_time(i)    = IMU_TimeTable.Time(imu_ind,:);
    

    % Grabbing the Quaternion
    quat_temp                = [IMU_TimeTable.Data(imu_ind,:)];

    % W X Y Z
    quat                = quaternion(quat_temp(1), quat_temp(2), quat_temp(3), quat_temp(4));
%     eul                 = quat2eul(quat);     
    Rot_Mat             = quat2rotm(quat_temp);

    %% De-bugging time stamps
%     fprintf("\n LiDAR Time stamp: %s \n GPS Time Stamp: %s \n GPS Time Diff: %s \n IMU Time Stamp: %s \n IMU Time Diff: %s \n", LiDAR_TimeTable.Time(i), gps_closest_time(i), gps_time_diff(i), imu_closest_time(i), imu_time_diff(i))

    %% Adjust point cloud

    % Step 1: Load pc
    % Step 2: Add GPS 
    % Step 3: Use rotatepoint to adjust the point cloud
    
    % Loading point cloud into friendly format
    xyzi                = [double(LiDAR_TimeTable.Data(i).Location) double(LiDAR_TimeTable.Data(i).Intensity)];
    
    % Removing nans and infsspeed
    xyzi                = xyzi( ~any( isnan(xyzi) | isinf(xyzi), 2),:);
    
    % Removing zeros
    % Necessary? Put off for now.........
    
    % Swapping the X, Y because of how it's orientated on the van
    xyzi_temp           = [xyzi(:,2) xyzi(:,1) xyzi(:,3) xyzi(:,4)];
    xyzi                = xyzi_temp;
    
    % Rotating the point cloud STEP 1: Rotate the cloud 90 degrees
    % counter clockwise to line up with the IMU frame
    for j = 1:1:length(xyzi(:,1))
        xyzi(j,1:3)         = xyzi(j,1:3) * PCD_ROT_OFFSET;
    end
    
    % Rotating the point cloud STEP 2: Use the IMU to adjust the
    % orientation of the point cloud
%     xyzi(:,1:3)          = rotatepoint(quat,[xyzi(:,1) xyzi(:,2) xyzi(:,3)]);
    for k = 1:1:length(xyzi(:,1))
        xyzi(k,1:3)         = Rot_Mat * xyzi(k,1:3)';
    end
    
    % Adding GPS offset
    xyzi(:,1)            = (xyzi(:,1)) + dx;
    xyzi(:,2)            = (xyzi(:,2)) + dy;
    xyzi(:,3)            = (xyzi(:,3)) + alt;
    
    % Storing dx, dy for debugging
    dxy_store = [dxy_store; dx dy alt];
    
    %% Apphend to overall point cloud

    XYZI_Apphend{i}      = xyzi;

    %% Weight bar

    % You heard me
%         waitbar(i/(num_pc),f,sprintf('%1.1f',(i/num_pc*100)))

    % clear dx dy xyzi

end

%     close(f)

disp('Processing complete, exporting array to point cloud object...')

%     Export_Cloud    = pointCloud([XYZI_Apphend(:,1) XYZI_Apphend(:,2) XYZI_Apphend(:,3)], 'Intensity', XYZI_Apphend(:,4));

disp('Point cloud object created. Saving to .pcd...')

%     FileName = string(export_dir) + "/Export_Cloud.pcd";

disp('Point cloud saved to .pcd! Plotting figures...')

figure
for i = loop_array

    % Displaying the resulting point cloud
    
%     pcshow(Export_Cloud)  
    scatter3(XYZI_Apphend{i}(:,1), XYZI_Apphend{i}(:,2), XYZI_Apphend{i}(:,3), '.')
    hold all
    scatter3(dxy_store(:,1), dxy_store(:,2), dxy_store(:,3), 'r*', 'LineWidth', 5)
    view([0 0 90])
    axis equal

end


%% Making the plots prettier
% gps_time_diff   = nonzeros(gps_time_diff);
% vect            = nonzeros(vect);
% duration_gps    = nonzeros(duration_gps);
% duration_lidar  = nonzeros(duration_lidar);
% speed           = nonzeros(speed);
% lat             = nonzeros(lat);
% lon             = nonzeros(lon);

figure
tiledlayout(2,2);

nexttile
scatter(loop_array,gps_time_diff,'.')
xlabel('Point Cloud Number')
ylabel('Time (s)')
title('Time stamp difference')

nexttile
plot(loop_array,vect,'.-')
xlabel('Point Cloud Number')
ylabel('Dist (m)')
title('Distance Traveled')

nexttile
plot(loop_array,duration_gps,'ro-')
hold on
plot(loop_array,duration_lidar,'b.-')
xlabel('Point Cloud Number')
ylabel('Time Stamp (s)')
legend('GPS','LiDAR')
title('DT Check')
hold off

nexttile
plot(loop_array,speed,'.-')
xlabel('Point Cloud Number')
ylabel('Speed (m/s)')
title('Speed')

figure
tiledlayout(1,2);

nexttile
geoplot(lat,lon,'.','LineWidth', 3)

nexttile
scatter(dydx_store_test(:,1),dydx_store_test(:,2), '.', 'LineWidth', 3)
axis equal

disp('Point cloud saved! End program.')



%     gong_gong()




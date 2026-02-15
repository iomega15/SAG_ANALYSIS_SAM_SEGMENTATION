function [BWlumen, quality] = segmentLumenSAM(I, roi, debugFolder, baseName)
% SEGMENTLUMENSAM Simplified: SAM segmentation at corrected image center
    
    % Default output structure
    quality = struct('status', 'unknown', 'lumen_valid', false, 'confidence', 0);

    % Ensure RGB
    if ndims(I) == 2, Irgb = repmat(I, [1 1 3]); else, Irgb = I; end
    [H, W, ~] = size(Irgb);

    % =========================================================================
    % FIX 1: Calculate Center Ignoring the Bottom ROI
    % =========================================================================
    % Calculate how many pixels are in the bottom ROI
    h_roi = round(H * roi.bottomFrac);
    
    % The "valid" image height is the total height minus the ROI
    h_valid = H - h_roi;
    
    % Calculate center based on the valid top portion only
    target_x = round(W / 2);
    target_y = round(h_valid / 2);
    
    % Save Temp Image
    tempFile = fullfile(tempdir, 'temp_sam_input.png');
    imwrite(Irgb, tempFile);

    % Locate Checkpoint (in parent folder)
    checkpointFile = fullfile(fileparts(pwd), 'sam_vit_b_01ec64.pth');
    if ~exist(checkpointFile, 'file')
        if exist(fullfile(pwd, 'sam_vit_b_01ec64.pth'), 'file')
            checkpointFile = fullfile(pwd, 'sam_vit_b_01ec64.pth');
        else
            error('SAM checkpoint not found at: %s', checkpointFile);
        end
    end

    try
        % Locate Python Script (in parent folder)
        pyScriptPath = fullfile(fileparts(checkpointFile), 'sam_segment_center.py');
        if ~exist('sam_segment_center.py', 'file') && exist(pyScriptPath, 'file')
             scriptToRun = pyScriptPath;
        else
             scriptToRun = "sam_segment_center.py";
        end

        % =========================================================================
        % FIX 2: Pass 'target_x' and 'target_y' to Python
        % =========================================================================
        [lumen_mask_out, conf_score] = pyrunfile( ...
            scriptToRun, ...
            ["lumen_mask_out", "confidence_score"], ...
            image_path=tempFile, ...
            checkpoint_path=checkpointFile, ...
            target_x=int32(target_x), ...   % <--- Explicit X
            target_y=int32(target_y));      % <--- Explicit Y

        % Process Result
        BWlumen = logical(lumen_mask_out);
        
        if any(BWlumen(:))
            quality.status = 'good';
            quality.lumen_valid = true;
            quality.confidence = double(conf_score);
        else
            quality.status = 'empty_mask';
        end

        % Debug Figure (Visualize the NEW center point)
        if ~isempty(debugFolder) && exist(debugFolder, 'dir')
            fig = figure('Visible', 'off');
            subplot(1,2,1); 
            imshow(Irgb); 
            hold on; 
            % Draw the Valid Area limit
            yLine = H - h_roi;
            line([1 W], [yLine yLine], 'Color', 'b', 'LineStyle', '--');
            % Draw the Center Point
            plot(target_x, target_y, 'r+', 'MarkerSize', 20, 'LineWidth', 2); 
            hold off;
            title('Input (Red=Corrected Center, Blue=ROI Limit)');
            
            subplot(1,2,2); 
            imshow(labeloverlay(Irgb, BWlumen, 'Colormap', [0 1 0], 'Transparency', 0.4));
            title(sprintf('Mask (Conf: %.2f)', quality.confidence));
            
            saveas(fig, fullfile(debugFolder, [baseName '_SAM_Center.png']));
            close(fig);
        end

    catch ME
        warning('SAM Error: %s', ME.message);
        BWlumen = false(H, W);
        quality.status = 'error';
    end

    if exist(tempFile, 'file'), delete(tempFile); end
end
function [folder_name] = make_clean_folder(folder_name)
    if exist(folder_name, 'dir')
        try
            % First attempt to remove
            rmdir(folder_name, 's');
        catch
            % If it fails, wait and retry once
            fprintf('Folder "%s" is locked. Retrying cleanup in 2 seconds...\n', folder_name);
            pause(2.0); 
            
            try
                rmdir(folder_name, 's');
            catch ME
                % HARD STOP: Do not allow the script to continue
                fprintf('\nFATAL ERROR: Could not clean folder "%s".\n', folder_name);
                fprintf('Ensure no images are open in IrfanView or other viewers.\n');
                error('CleanFolder:LockedDirectory', 'Directory is locked by another process: %s', ME.message);
            end
        end
    end
    
    % Re-create the folder
    mkdir(folder_name);
end
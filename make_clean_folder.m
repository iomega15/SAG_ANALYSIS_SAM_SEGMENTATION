function [folder_name] = make_clean_folder(folder_name)


if(exist(folder_name,'dir'))
    
    rmdir(folder_name,'s');
    mkdir(folder_name);
    
else
    
    mkdir(folder_name);
    
end %exist(folder_name,'dir')


end

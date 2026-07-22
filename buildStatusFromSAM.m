function statusCol = buildStatusFromSAM(T)
%BUILDSTATUSFROMSAM  Per-image channel status from raw SAM polarity.
%   valid+bright -> 'open', valid+dark -> 'occluded', else -> 'failed'.
%   Shared by plotOcclusionHeatmap (qualitative map) and
%   computeChannelStateMatrix (used by the sag figures) so both see the
%   identical per-image status.
    statusCol = repmat({'failed'}, height(T), 1);
    for i = 1:height(T)
        if ~T.SAM_LumenValid(i)
            statusCol{i} = 'failed';
        else
            pol = T.SAM_Polarity{i};
            switch pol
                case 'bright'
                    statusCol{i} = 'open';
                case 'dark'
                    statusCol{i} = 'occluded';
                otherwise
                    statusCol{i} = 'failed';
            end
        end
    end
end

using System;
using System.Collections.Generic;
using Domain.InGame;

public interface ISaveLoadViewModel
{
    IReadOnlyList<SaveDataFileDTO> SlotList { get; }
    int SelectedSlotIndex { get; }
    GlobalProgressDataDTO GlobalProgress { get; }
    bool IsSaveActionAllowed { get; }
    event Action OnStateChanged;
    event Action OnCloseRequested;

    void InitializeViewModel(bool isSaveAllowed);
    void SelectSlot(int index);
    void ExecuteLoad();
    void ExecuteSave(SaveDataFileDTO currentData);
    void ExecuteDelete();
    void Close();
}

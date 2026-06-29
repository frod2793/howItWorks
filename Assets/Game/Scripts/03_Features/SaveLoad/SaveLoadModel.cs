using System;
using System.IO;
using UnityEngine;
using Features.InGame;
using Domain.InGame;

public class SaveLoadModel
{
    private readonly IInGameSaveSystem m_saveSystem;

    public SaveLoadModel(IInGameSaveSystem saveSystem)
    {
        m_saveSystem = saveSystem;
    }

    public SaveDataFileDTO LoadSlotData(int slotId)
    {
        if (m_saveSystem == null)
        {
            return null;
        }
        return m_saveSystem.LoadSessionData(slotId);
    }

    public void SaveSlotData(SaveDataFileDTO data)
    {
        if (m_saveSystem == null || data == null)
        {
            return;
        }
        m_saveSystem.SaveSessionData(data);
    }

    public void DeleteSlotData(int slotId)
    {
        if (m_saveSystem == null)
        {
            return;
        }
        string saveDir = Path.Combine(Application.persistentDataPath, "Saves");
        string dataPath = Path.Combine(saveDir, string.Format("save_slot_{0}.json", slotId));
        string imgPath = Path.Combine(saveDir, string.Format("save_slot_{0}.png", slotId));

        if (File.Exists(dataPath))
        {
            File.Delete(dataPath);
        }
        if (File.Exists(imgPath))
        {
            File.Delete(imgPath);
        }
    }

    public GlobalProgressDataDTO GetGlobalProgress()
    {
        if (m_saveSystem == null)
        {
            return new GlobalProgressDataDTO();
        }
        return m_saveSystem.LoadGlobalProgress();
    }
}

using System;
using System.IO;
using Domain.InGame;
using UnityEngine;

namespace Features.InGame
{
    public interface IInGameSaveSystem
    {
        void SaveSessionData(SaveDataFileDTO data);
        SaveDataFileDTO LoadSessionData(int slotId);
        void SaveGlobalProgress(GlobalProgressDataDTO progress);
        GlobalProgressDataDTO LoadGlobalProgress();
    }

    public class InGameSaveSystem : IInGameSaveSystem
    {
        private readonly string m_saveDirectory;
        private readonly string m_globalProgressFile;

        public InGameSaveSystem()
        {
            m_saveDirectory = Path.Combine(Application.persistentDataPath, "Saves");
            m_globalProgressFile = Path.Combine(m_saveDirectory, "global_progress.json");

            if (Directory.Exists(m_saveDirectory) == false)
            {
                Directory.CreateDirectory(m_saveDirectory);
            }
        }

        public void SaveSessionData(SaveDataFileDTO data)
        {
            if (data == null)
            {
                return;
            }
            string path = Path.Combine(m_saveDirectory, string.Format("save_slot_{0}.json", data.slotId));
            string json = JsonUtility.ToJson(data, true);
            File.WriteAllText(path, json);
        }

        public SaveDataFileDTO LoadSessionData(int slotId)
        {
            string path = Path.Combine(m_saveDirectory, string.Format("save_slot_{0}.json", slotId));
            if (File.Exists(path) == false)
            {
                return null;
            }
            string json = File.ReadAllText(path);
            return JsonUtility.FromJson<SaveDataFileDTO>(json);
        }

        public void SaveGlobalProgress(GlobalProgressDataDTO progress)
        {
            if (progress == null)
            {
                return;
            }
            string json = JsonUtility.ToJson(progress, true);
            File.WriteAllText(m_globalProgressFile, json);
        }

        public GlobalProgressDataDTO LoadGlobalProgress()
        {
            if (File.Exists(m_globalProgressFile) == false)
            {
                return new GlobalProgressDataDTO();
            }
            string json = File.ReadAllText(m_globalProgressFile);
            return JsonUtility.FromJson<GlobalProgressDataDTO>(json);
        }
    }
}

using UnityEngine;
using System.Collections.Generic;
using System.Linq;

public class PopupDataProvider
{
    private const string DATA_PATH = "Data/PopupData";
    private Dictionary<string, PopupEntryDTO> m_popupCache;

    private void LoadData()
    {
        if (m_popupCache != null)
        {
            return;
        }

        var jsonAsset = Resources.Load<TextAsset>(DATA_PATH);
        if (jsonAsset == null)
        {
            Debug.LogError($"[PopupDataProvider] 데이터 로드 실패: {DATA_PATH}");
            m_popupCache = new Dictionary<string, PopupEntryDTO>();
            return;
        }

        var data = JsonUtility.FromJson<PopupDataDTO>(jsonAsset.text);
        if (data != null && data.Popups != null)
        {
            m_popupCache = data.Popups.ToDictionary(p => p.Key);
        }
        else
        {
            m_popupCache = new Dictionary<string, PopupEntryDTO>();
        }
    }

    public PopupEntryDTO GetPopupData(string key)
    {
        LoadData();

        if (m_popupCache.TryGetValue(key, out var data))
        {
            return data;
        }

        Debug.LogWarning($"[PopupDataProvider] 키 조회 실패: {key}");
        return new PopupEntryDTO { Message = "알 수 없는 요청입니다.", Subtitle = "" };
    }

    public List<string> GetAllKeys()
    {
        LoadData();
        return m_popupCache.Keys.ToList();
    }
}

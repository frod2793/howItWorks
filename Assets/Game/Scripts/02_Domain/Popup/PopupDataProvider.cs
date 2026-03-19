using UnityEngine;
using System.Collections.Generic;
using System.Linq;

#region 내부 로직
/// <summary>
/// [설명]: JSON 파일로부터 팝업 데이터를 로드하고 키값으로 조회할 수 있게 해주는 제공자 클래스입니다.
/// </summary>
public class PopupDataProvider
{
    private const string DATA_PATH = "Data/PopupData";
    private Dictionary<string, PopupEntryDTO> m_popupCache;

    /// <summary>
    /// [설명]: 데이터를 로드하고 캐싱합니다.
    /// </summary>
    private void LoadData()
    {
        if (m_popupCache != null) return;

        var jsonAsset = Resources.Load<TextAsset>(DATA_PATH);
        if (jsonAsset == null)
        {
            Debug.LogError($"[PopupDataProvider] 데이터를 찾을 수 없습니다: {DATA_PATH}");
            m_popupCache = new Dictionary<string, PopupEntryDTO>();
            return;
        }

        var data = JsonUtility.FromJson<PopupDataDTO>(jsonAsset.text);
        m_popupCache = data?.Popups.ToDictionary(p => p.Key) ?? new Dictionary<string, PopupEntryDTO>();
    }

    /// <summary>
    /// [설명]: 지정된 키에 해당하는 팝업 데이터를 반환합니다.
    /// </summary>
    /// <param name="key">팝업 식별 키</param>
    /// <returns>해당하는 팝업 데이터 (없을 경우 기본값)</returns>
    public PopupEntryDTO GetPopupData(string key)
    {
        LoadData();

        if (m_popupCache.TryGetValue(key, out var data))
        {
            return data;
        }

        Debug.LogWarning($"[PopupDataProvider] 키를 찾을 수 없습니다: {key}");
        return new PopupEntryDTO { Message = "알 수 없는 요청입니다.", Subtitle = "" };
    }

    /// <summary>
    /// [설명]: 등록된 모든 팝업 데이터의 키 리스트를 반환합니다.
    /// </summary>
    /// <returns>키 리스트</returns>
    public List<string> GetAllKeys()
    {
        LoadData();
        return m_popupCache.Keys.ToList();
    }
}
#endregion

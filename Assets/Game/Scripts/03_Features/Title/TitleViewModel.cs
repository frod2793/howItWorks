using UnityEngine;
using System;
using Features.InGame;
using Domain.InGame;

#region 뷰모델 (ViewModel)
/// <summary>
/// [설명]: 타이틀 화면의 메뉴 선택 로직을 처리하는 뷰모델입니다.
/// </summary>
public class TitleViewModel : ITitleViewModel
{
    #region 내부 필드
    private readonly ISceneLoader m_sceneLoader;
    private readonly IInGameSaveSystem m_saveSystem;
    #endregion

    #region 프로퍼티
    /// <summary>
    /// [설명]: 팝업 조회를 위한 키값을 전달하는 이벤트입니다.
    /// </summary>
    public event Action<string> OnRequestPopup;
    public event Action OnRequestSettings;
    public event Action OnRequestSaveLoad;
    public event Action OnRequestEncyclopedia;

    public bool IsLoadGameActive
    {
        get
        {
            var saveData = m_saveSystem.LoadSessionData(0);
            if (saveData != null)
            {
                return true;
            }
            return false;
        }
    }

    public bool IsStoryTreeActive
    {
        get
        {
            var globalData = m_saveSystem.LoadGlobalProgress();
            if (globalData != null && globalData.unlockedEndings != null && globalData.unlockedEndings.Count >= 1)
            {
                return true;
            }
            return false;
        }
    }

    public string RecentEndingId
    {
        get
        {
            var globalData = m_saveSystem.LoadGlobalProgress();
            if (globalData != null && globalData.unlockedEndings != null && globalData.unlockedEndings.Count > 0)
            {
                return globalData.unlockedEndings[globalData.unlockedEndings.Count - 1];
            }
            return string.Empty;
        }
    }
    #endregion

    public TitleViewModel(ISceneLoader sceneLoader, IInGameSaveSystem saveSystem)
    {
        m_sceneLoader = sceneLoader;
        m_saveSystem = saveSystem;
    }


    #region 공개 메서드
    public void NewGame()
    {
        Debug.Log("[TitleViewModel] 인게임 씬 로드 시작");
        
        if (m_sceneLoader != null)
        {
            m_sceneLoader.LoadScene("InGame", 0.5f);
        }
    }

    public void LoadGame()
    {
        if (OnRequestSaveLoad != null)
        {
            OnRequestSaveLoad.Invoke();
        }
    }

    public void OpenSettings()
    {
        if (OnRequestSettings != null)
        {
            OnRequestSettings.Invoke();
        }
    }

    public void OpenArchive()
    {
        if (OnRequestPopup != null)
        {
            OnRequestPopup.Invoke("Sorry");
        }
    }

    public void OpenEncyclopedia()
    {
        if (OnRequestEncyclopedia != null)
        {
            OnRequestEncyclopedia.Invoke();
        }
    }

    public void OpenStoryTree()
    {
        if (OnRequestPopup != null)
        {
            OnRequestPopup.Invoke("Sorry");
        }
    }

    public void OpenCredits()
    {
        if (OnRequestPopup != null)
        {
            OnRequestPopup.Invoke("Sorry");
        }
    }

    public void QuitGame()
    {
        Debug.Log("[TitleViewModel] 게임 종료 호출");
        Application.Quit();
    }
    #endregion
}
#endregion

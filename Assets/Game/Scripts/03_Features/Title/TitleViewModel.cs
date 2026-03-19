using UnityEngine;
using System;

#region 뷰모델 (ViewModel)
/// <summary>
/// [설명]: 타이틀 화면의 메뉴 선택 로직을 처리하는 뷰모델입니다.
/// </summary>
public class TitleViewModel : ITitleViewModel
{
    #region 내부 필드
    private readonly ISceneLoader m_sceneLoader;
    #endregion

    #region 프로퍼티
    /// <summary>
    /// [설명]: 팝업 조회를 위한 키값을 전달하는 이벤트입니다.
    /// </summary>
    public event Action<string> OnRequestPopup;
    #endregion

    public TitleViewModel(ISceneLoader sceneLoader)
    {
        m_sceneLoader = sceneLoader;
    }

    #region 공개 메서드
    public void NewGame()
    {
        Debug.Log("[TitleViewModel] 새 게임 시작! 인게임 씬으로 이동합니다.");
        
        if (m_sceneLoader != null)
        {
            m_sceneLoader.LoadScene("InGame", 0.5f);
        }
    }

    public void LoadGame()
    {
        OnRequestPopup?.Invoke("Sorry");
    }

    public void OpenSettings()
    {
        OnRequestPopup?.Invoke("Sorry");
    }

    public void OpenArchive()
    {
        OnRequestPopup?.Invoke("Sorry");
    }
    #endregion
}
#endregion

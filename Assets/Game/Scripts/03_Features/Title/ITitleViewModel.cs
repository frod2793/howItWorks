using System;

#region 뷰모델 (ViewModel)
/// <summary>
/// [설명]: 게임 타이틀 화면의 각종 버튼 명령을 정의하는 뷰모델 인터페이스입니다.
/// </summary>
public interface ITitleViewModel
{
    void NewGame();
    void LoadGame();
    void OpenSettings();
    void OpenArchive();
}
#endregion

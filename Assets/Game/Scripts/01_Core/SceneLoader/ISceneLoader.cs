using Cysharp.Threading.Tasks;

#region 내부 로직
/// <summary>
/// [설명]: 씬 전환 및 데이터 전달을 담당하는 서비스 인터페이스입니다.
/// </summary>
public interface ISceneLoader
{
    /// <summary>
    /// [설명]: 지정된 씬으로 트랜지션 효과와 함께 이동합니다.
    /// </summary>
    /// <param name="sceneName">이동할 씬 이름</param>
    /// <param name="startDelay">트랜지션 시작 전 대기 시간</param>
    void LoadScene(string sceneName, float startDelay = 0f);

    /// <summary>
    /// [설명]: 데이터를 수반하여 지정된 씬으로 이동합니다. (향후 DTO 연동용)
    /// </summary>
    /// <typeparam name="T">데이터 타입</typeparam>
    /// <param name="sceneName">이동할 씬 이름</param>
    /// <param name="data">전달할 데이터</param>
    /// <param name="startDelay">대기 시간</param>
    void LoadSceneWithData<T>(string sceneName, T data, float startDelay = 0f);
}
#endregion

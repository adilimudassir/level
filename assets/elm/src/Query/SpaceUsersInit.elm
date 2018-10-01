module Query.SpaceUsersInit exposing (Response, request)

import Connection exposing (Connection)
import GraphQL exposing (Document)
import Group exposing (Group)
import Id exposing (Id)
import Json.Decode as Decode exposing (Decoder, field, list)
import Json.Encode as Encode
import Repo exposing (Repo)
import Route.SpaceUsers exposing (Params(..))
import Session exposing (Session)
import Space exposing (Space)
import SpaceUser exposing (SpaceUser)
import Task exposing (Task)


type alias Response =
    { viewerId : Id
    , spaceId : Id
    , bookmarkIds : List Id
    , spaceUserIds : Connection Id
    , repo : Repo
    }


type alias Data =
    { viewer : SpaceUser
    , space : Space
    , bookmarks : List Group
    , spaceUsers : Connection SpaceUser
    }


document : Params -> Document
document params =
    GraphQL.toDocument
        """
        query SpaceUsersInit(
          $spaceSlug: ID!,
          $first: Int,
          $last: Int,
          $before: Cursor,
          $after: Cursor
        ) {
          spaceUser(spaceSlug: $spaceSlug) {
            ...SpaceUserFields
            space {
              ...SpaceFields
              spaceUsers(
                first: $first,
                last: $last,
                before: $before,
                after: $after,
                orderBy: { field: LAST_NAME, direction: ASC }
              ) {
                ...SpaceUserConnectionFields
              }
            }
            bookmarks {
              ...GroupFields
            }
          }
        }
        """
        [ SpaceUser.fragment
        , Space.fragment
        , Group.fragment
        , Connection.fragment "SpaceUserConnection" SpaceUser.fragment
        ]


variables : Params -> Int -> Maybe Encode.Value
variables params limit =
    let
        spaceSlug =
            Encode.string (Route.SpaceUsers.getSpaceSlug params)

        encLimit =
            Encode.int limit

        query =
            Encode.string (Route.SpaceUsers.getQuery params)

        values =
            case
                ( Route.SpaceUsers.getBefore params
                , Route.SpaceUsers.getAfter params
                )
            of
                ( Just before, Nothing ) ->
                    [ ( "spaceSlug", spaceSlug )
                    , ( "last", encLimit )
                    , ( "before", Encode.string before )
                    , ( "query", query )
                    ]

                ( Nothing, Just after ) ->
                    [ ( "spaceSlug", spaceSlug )
                    , ( "first", encLimit )
                    , ( "after", Encode.string after )
                    , ( "query", query )
                    ]

                ( _, _ ) ->
                    [ ( "spaceSlug", spaceSlug )
                    , ( "first", encLimit )
                    , ( "query", query )
                    ]
    in
    Just (Encode.object values)


decoder : Decoder Data
decoder =
    Decode.at [ "data", "spaceUser" ] <|
        Decode.map4 Data
            SpaceUser.decoder
            (field "space" Space.decoder)
            (field "bookmarks" (list Group.decoder))
            (Decode.at [ "space", "spaceUsers" ] (Connection.decoder SpaceUser.decoder))


buildResponse : ( Session, Data ) -> ( Session, Response )
buildResponse ( session, data ) =
    let
        repo =
            Repo.empty
                |> Repo.setSpaceUser data.viewer
                |> Repo.setSpace data.space
                |> Repo.setGroups data.bookmarks
                |> Repo.setSpaceUsers (Connection.toList data.spaceUsers)

        resp =
            Response
                (SpaceUser.id data.viewer)
                (Space.id data.space)
                (List.map Group.id data.bookmarks)
                (Connection.map SpaceUser.id data.spaceUsers)
                repo
    in
    ( session, resp )


request : Params -> Int -> Session -> Task Session.Error ( Session, Response )
request params limit session =
    GraphQL.request (document params) (variables params limit) decoder
        |> Session.request session
        |> Task.map buildResponse
